import type { Server, ServerWebSocket, WebSocketHandler } from "bun";
import { OpenCodeError } from "../opencode.ts";
import type { TerminalService } from "../terminals.ts";
import type { HubSocketData, TerminalSocketData } from "./socket.ts";
import { error } from "./support.ts";

/**
 * Proxies one terminal WebSocket per client through the hub. OpenCode's PTY
 * socket stays upstream; the app only ever needs the hub's Bearer token.
 */
export class TerminalSockets {
  constructor(private readonly terminals: Pick<TerminalService, "socketTarget">) {}

  /**
   * Resolves the upstream socket before upgrading, so authentication and
   * unknown-terminal failures get a normal HTTP error instead of a socket that
   * closes immediately.
   */
  async upgrade(
    request: Request,
    server: Server<HubSocketData>,
    terminalID: string,
    location: string | null,
    cursor: string | null,
  ): Promise<Response | undefined> {
    let target: { url: string; authorization: string; location: string };
    try {
      target = await this.terminals.socketTarget(
        terminalID,
        location ?? undefined,
        cursor ?? undefined,
      );
    } catch (caught) {
      if (caught instanceof OpenCodeError) {
        return error(caught.message, caught.status ?? 502);
      }
      throw caught;
    }

    const data: TerminalSocketData = {
      kind: "terminal",
      ...target,
      terminalID,
    };
    if (!server.upgrade(request, { data })) {
      return error("Could not upgrade the terminal connection", 500);
    }
    return undefined;
  }

  readonly handlers: WebSocketHandler<HubSocketData> = {
    data: {} as HubSocketData,
    // A terminal can sit at a prompt for hours; Bun's default 120-second idle
    // timeout would otherwise disconnect it.
    idleTimeout: 0,

    open: (ws) => {
      const data = ws.data as TerminalSocketData;
      const upstream = new WebSocket(data.url, {
        headers: { Authorization: data.authorization },
      });
      upstream.binaryType = "arraybuffer";
      data.upstream = upstream;

      upstream.onopen = () => {
        // The client may have gone away while the upstream was connecting.
        if (data.closed) {
          try {
            upstream.close();
          } catch {
            // Already closed.
          }
        }
      };

      upstream.onmessage = (event) => {
        if (data.closed) return;
        const message = event.data;
        if (typeof message === "string") {
          ws.send(message);
        } else if (message instanceof ArrayBuffer) {
          ws.send(new Uint8Array(message));
        } else {
          ws.send(message as Blob);
        }
      };

      upstream.onclose = (event) => {
        const code = normalizeCloseCode(event.code);
        safeClose(ws, code, event.reason || "terminal closed");
      };

      upstream.onerror = () => {
        safeClose(ws, 1011, "terminal connection failed");
      };
    },

    message: (ws, message) => {
      const data = ws.data as TerminalSocketData;
      const upstream = data.upstream;
      if (!upstream || upstream.readyState !== WebSocket.OPEN) return;
      upstream.send(message);
    },

    close: (ws) => {
      const data = ws.data as TerminalSocketData;
      data.closed = true;
      const upstream = data.upstream;
      data.upstream = undefined;
      if (upstream && upstream.readyState < WebSocket.CLOSING) {
        try {
          upstream.close();
        } catch {
          // The upstream socket never finished connecting.
        }
      }
    },
  };
}

const SENDABLE_CLOSE_CODES = new Set([
  1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014,
]);

function normalizeCloseCode(code: number): number {
  // Codes outside the WebSocket-sendable range (notably 1005/1006) cannot be
  // echoed to a peer, so report an abnormal closure instead.
  if (SENDABLE_CLOSE_CODES.has(code) || (code >= 3_000 && code <= 4_999)) {
    return code;
  }
  return 1011;
}

function safeClose(ws: ServerWebSocket<HubSocketData>, code: number, reason: string): void {
  try {
    ws.close(code, reason);
  } catch {
    try {
      ws.close();
    } catch {
      // The downstream socket already went away.
    }
  }
}
