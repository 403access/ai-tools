import type { HubClient } from "./hub.ts";

export interface SocketReadOptions {
  /** Milliseconds to keep the socket open. Capped at 20s. */
  waitMs?: number;
  /** Close after this much quiet time once output has arrived. 0 disables idle close. */
  idleMs?: number;
  /** Text to send after the socket opens, for example a shell command plus `\r`. */
  input?: string;
  /** Keep CSI/OSC colour escapes in the returned text. */
  raw?: boolean;
  /** Cap the captured text. Defaults to 256 KiB. */
  maxBytes?: number;
}

export interface SocketReadResult {
  text: string;
  bytes: number;
  messages: number;
  truncated: boolean;
  closed: boolean;
}

/**
 * Connects to one hub WebSocket, optionally sends input, and collects what the
 * other side says for a bounded window. Used for OpenCode terminals and NixOS
 * serial consoles: the hub already authenticates the upstream connection, so
 * this only needs the hub token.
 */
export function readSocket(
  client: HubClient,
  path: string,
  params: Record<string, string | number | boolean | undefined> = {},
  options: SocketReadOptions = {},
): Promise<SocketReadResult> {
  const waitMs = Math.min(Math.max(options.waitMs ?? 1_500, 100), 20_000);
  const idleMs = Math.min(Math.max(options.idleMs ?? 350, 0), 10_000);
  const maxBytes = Math.min(Math.max(options.maxBytes ?? 262_144, 1_024), 2_000_000);
  const url = client.socketURL(path, params);

  return new Promise((resolve, reject) => {
    const chunks: Uint8Array[] = [];
    let bytes = 0;
    let messages = 0;
    let truncated = false;
    let closed = false;
    let settled = false;
    let idle: ReturnType<typeof setTimeout> | undefined;
    let deadline: ReturnType<typeof setTimeout> | undefined;
    let connectDeadline: ReturnType<typeof setTimeout> | undefined;
    let opened = false;

    let socket: WebSocket;
    try {
      socket = new WebSocket(url);
    } catch (caught) {
      reject(caught instanceof Error ? caught : new Error(String(caught)));
      return;
    }

    connectDeadline = setTimeout(() => {
      if (!opened) finish(new Error("Timed out connecting to the hub stream."));
    }, 10_000);

    const finish = (error?: Error) => {
      if (settled) return;
      settled = true;
      if (idle) clearTimeout(idle);
      if (deadline) clearTimeout(deadline);
      if (connectDeadline) clearTimeout(connectDeadline);
      try {
        socket.close();
      } catch {
        // Already closed.
      }
      if (error) {
        reject(error);
        return;
      }
      resolve({
        text: decodeChunks(chunks, options.raw === true),
        bytes,
        messages,
        truncated,
        closed,
      });
    };

    socket.onopen = () => {
      opened = true;
      if (connectDeadline) clearTimeout(connectDeadline);
      if (options.input !== undefined) {
        try {
          socket.send(options.input);
        } catch (caught) {
          finish(caught instanceof Error ? caught : new Error(String(caught)));
          return;
        }
      }
      deadline = setTimeout(() => finish(), waitMs);
    };

    socket.onmessage = (event) => {
      const bytesValue = toBytes(event.data);
      if (!bytesValue) return;
      // Terminal sockets send one binary replay boundary: 0x00 + {"cursor":…}.
      const body =
        bytesValue[0] === 0 && bytesValue.length > 1
          ? bytesValue.subarray(1)
          : bytesValue;
      messages += 1;
      if (bytes > maxBytes) {
        truncated = true;
        return;
      }
      const remaining = maxBytes - bytes;
      const kept = body.length > remaining ? body.subarray(0, remaining) : body;
      if (kept.length < body.length) truncated = true;
      chunks.push(kept);
      bytes += kept.length;

      if (idleMs > 0) {
        if (idle) clearTimeout(idle);
        idle = setTimeout(() => finish(), idleMs);
      }
    };

    socket.onerror = () => {
      finish(
        messages === 0
          ? new Error("The hub closed the stream before any data arrived.")
          : undefined,
      );
    };

    socket.onclose = (event) => {
      closed = true;
      if (!settled) {
        if (messages === 0 && event.code !== 1000) {
          finish(
            new Error(
              `The hub stream closed (${event.code}${event.reason ? `: ${event.reason}` : ""}).`,
            ),
          );
        } else {
          finish();
        }
      }
    };
  });
}

function toBytes(data: unknown): Uint8Array | null {
  if (typeof data === "string") return new TextEncoder().encode(data);
  if (data instanceof ArrayBuffer) return new Uint8Array(data);
  if (ArrayBuffer.isView(data)) {
    return new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  }
  return null;
}

function decodeChunks(chunks: Uint8Array[], raw: boolean): string {
  const decoder = new TextDecoder();
  let text = "";
  for (const chunk of chunks) {
    text += decoder.decode(chunk, { stream: true });
  }
  text += decoder.decode();
  if (raw) return text;
  return stripTerminalControl(text);
}

/** Removes colour and cursor escapes while keeping the readable terminal text. */
export function stripTerminalControl(value: string): string {
  return value
    .replace(/\u001b\][^\u0007]*(?:\u0007|\u001b\\)/g, "")
    .replace(/\u001b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\u001b[@-_]/g, "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/[^\S\n]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trimEnd();
}