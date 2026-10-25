import { accessSync, constants, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

export interface RemoteDisplay {
  id: number;
  name: string;
  width: number;
  height: number;
  scale: number;
  primary: boolean;
}

export interface RemoteStatus {
  /** The helper binary exists on this machine. */
  available: boolean;
  /** The helper process is currently alive. */
  running: boolean;
  viewers: number;
  version: string | null;
  screenRecording: boolean;
  accessibility: boolean;
  displays: RemoteDisplay[];
  displayID: number | null;
  fps: number;
  quality: number;
  maxWidth: number;
  streaming: boolean;
  error: string | null;
}

export interface RemoteConfigureInput {
  fps?: number;
  quality?: number;
  maxWidth?: number;
  displayID?: number;
}

export type RemoteEvent =
  | { type: "status"; status: RemoteStatus }
  | { type: "frame"; data: Uint8Array }
  | { type: "log"; level: string; message: string };

export interface RemoteHost {
  status(): Promise<RemoteStatus>;
  configure(input: RemoteConfigureInput): RemoteStatus;
  requestPermissions(input: { screenRecording?: boolean; accessibility?: boolean }): RemoteStatus;
  sendInput(message: Record<string, unknown>): void;
  addViewer(): void;
  removeViewer(): void;
  subscribe(listener: (event: RemoteEvent) => void): () => void;
  latestFrame(): Uint8Array | null;
}

const MAX_MESSAGE_BYTES = 32 * 1024 * 1024;
const DEFAULT_FPS = 12;
const DEFAULT_QUALITY = 0.6;
const DEFAULT_MAX_WIDTH = 1600;

export function emptyRemoteStatus(error: string | null = null): RemoteStatus {
  return {
    available: false,
    running: false,
    viewers: 0,
    version: null,
    screenRecording: false,
    accessibility: false,
    displays: [],
    displayID: null,
    fps: DEFAULT_FPS,
    quality: DEFAULT_QUALITY,
    maxWidth: DEFAULT_MAX_WIDTH,
    streaming: false,
    error,
  };
}

/**
 * Owns the Swift helper that captures the Mac display and posts input events.
 *
 * The helper speaks a tiny framed protocol over stdio (see
 * `Sources/OpenCodeBarRemoteHost/Wire.swift`), so the hub can stay a single Bun
 * process and relay frames to WebSocket clients without an extra port.
 */
export class RemoteHostService implements RemoteHost {
  private readonly helperPath: string | null;
  private readonly listeners = new Set<(event: RemoteEvent) => void>();
  private child: Bun.Subprocess<"pipe", "pipe", "pipe"> | null = null;
  private buffer = new Uint8Array(0);
  private statusValue: RemoteStatus;
  private frame: Uint8Array | null = null;
  private viewers = 0;
  private stopTimer: ReturnType<typeof setTimeout> | null = null;
  private shuttingDown = false;
  private firstStatus: Promise<void> | null = null;
  private resolveFirstStatus: (() => void) | null = null;
  private receivedStatus = false;

  constructor(options: { helperPath?: string } = {}) {
    const disabled =
      options.helperPath === undefined &&
      /^(0|false|off|no)$/i.test(process.env.OPENCODEBAR_REMOTE?.trim() ?? "");
    this.helperPath = disabled ? null : options.helperPath ?? resolveHelper();
    this.statusValue = emptyRemoteStatus(
      disabled
        ? "Remote desktop is disabled. Restart the hub without OPENCODEBAR_REMOTE=0."
        : this.helperPath
          ? null
          : "Remote host helper not found. Run `make remote-host` and restart the hub.",
    );
    this.statusValue.available = Boolean(this.helperPath);
  }

  status(): Promise<RemoteStatus> {
    if (!this.ensureChild()) return Promise.resolve(this.statusValue);
    if (!this.firstStatus) {
      this.firstStatus = new Promise<void>((resolvePromise) => {
        this.resolveFirstStatus = resolvePromise;
      });
      // Do not leave the app waiting forever if ScreenCaptureKit is slow to
      // answer. The next status call picks up the real snapshot.
      setTimeout(() => this.resolveFirstStatus?.(), 2_500);
    }
    const wait = this.firstStatus;
    const first = !this.receivedStatus;
    // Ask the helper for a fresh snapshot so permission changes made in System
    // Settings show up without waiting for the next capture event.
    this.send({ type: "status" });
    if (!first) {
      return new Promise<RemoteStatus>((resolvePromise) => {
        setTimeout(() => resolvePromise(this.statusValue), 120);
      });
    }
    return Promise.race([
      wait.then(() => this.statusValue),
      new Promise<RemoteStatus>((resolvePromise) => {
        setTimeout(() => resolvePromise(this.statusValue), 2_600);
      }),
    ]);
  }

  configure(input: RemoteConfigureInput): RemoteStatus {
    const patch: RemoteConfigureInput = {};
    if (Number.isFinite(input.fps)) {
      patch.fps = Math.min(Math.max(Math.round(input.fps!), 1), 30);
      this.statusValue.fps = patch.fps;
    }
    if (Number.isFinite(input.quality)) {
      patch.quality = Math.min(Math.max(input.quality!, 0.1), 1);
      this.statusValue.quality = patch.quality;
    }
    if (Number.isFinite(input.maxWidth)) {
      patch.maxWidth = Math.min(Math.max(Math.round(input.maxWidth!), 480), 3840);
      this.statusValue.maxWidth = patch.maxWidth;
    }
    if (Number.isFinite(input.displayID) && input.displayID! > 0) {
      patch.displayID = Math.round(input.displayID!);
      this.statusValue.displayID = patch.displayID;
    }

    if (Object.keys(patch).length > 0) {
      this.send({ type: "configure", ...patch });
      this.emitStatus();
    }
    return this.statusValue;
  }

  requestPermissions(input: {
    screenRecording?: boolean;
    accessibility?: boolean;
  }): RemoteStatus {
    this.send({
      type: "permissions",
      screenRecording: input.screenRecording === true,
      accessibility: input.accessibility === true,
    });
    return this.statusValue;
  }

  sendInput(message: Record<string, unknown>): void {
    this.send(message);
  }

  addViewer(): void {
    this.viewers += 1;
    this.statusValue.viewers = this.viewers;
    if (this.stopTimer) {
      clearTimeout(this.stopTimer);
      this.stopTimer = null;
    }
    if (this.ensureChild()) this.send({ type: "start" });
    this.emitStatus();
  }

  removeViewer(): void {
    this.viewers = Math.max(this.viewers - 1, 0);
    this.statusValue.viewers = this.viewers;
    if (this.viewers > 0) return;

    if (this.stopTimer) clearTimeout(this.stopTimer);
    this.stopTimer = setTimeout(() => {
      this.stopTimer = null;
      if (this.viewers > 0) return;
      this.send({ type: "stop" });
    }, 8_000);
    this.emitStatus();
  }

  subscribe(listener: (event: RemoteEvent) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  latestFrame(): Uint8Array | null {
    return this.frame;
  }

  shutdown(): void {
    this.shuttingDown = true;
    if (this.stopTimer) {
      clearTimeout(this.stopTimer);
      this.stopTimer = null;
    }
    this.send({ type: "stop" });
    const child = this.child;
    this.child = null;
    if (child) {
      try {
        child.kill();
      } catch {
        // Already gone.
      }
    }
  }

  // MARK: - Helper process

  private ensureChild(): boolean {
    if (this.child) return true;
    if (this.shuttingDown) return false;
    if (!this.helperPath) {
      this.statusValue.available = false;
      return false;
    }

    try {
      const child = Bun.spawn({
        cmd: [this.helperPath],
        cwd: dirname(this.helperPath),
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
        env: process.env,
      });
      this.child = child;
      this.statusValue.available = true;
      this.statusValue.running = true;
      this.firstStatus = null;
      this.resolveFirstStatus = null;
      this.receivedStatus = false;

      void this.readStdout(child);
      void this.readStderr(child);
      void child.exited.then((code) => {
        if (this.child === child) this.child = null;
        this.statusValue.running = false;
        this.statusValue.streaming = false;
        if (!this.shuttingDown && code !== 0) {
          this.statusValue.error = `Remote host helper exited (${code}).`;
        }
        this.emitStatus();
      });
      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.statusValue.available = Boolean(this.helperPath);
      this.statusValue.running = false;
      this.statusValue.error = `Could not start the remote host helper: ${message}`;
      this.emitStatus();
      return false;
    }
  }

  private async readStdout(child: Bun.Subprocess<"pipe", "pipe", "pipe">): Promise<void> {
    try {
      for await (const chunk of child.stdout) {
        this.consume(chunk);
      }
    } catch (error) {
      this.log(`Reading helper output failed: ${String(error)}`, "error");
    }
  }

  private async readStderr(child: Bun.Subprocess<"pipe", "pipe", "pipe">): Promise<void> {
    const decoder = new TextDecoder();
    try {
      for await (const chunk of child.stderr) {
        const text = decoder.decode(chunk).trim();
        // The helper already streams structured log frames to clients; this
        // copy is only for the hub's own terminal.
        if (text) console.log(`[remote-host] ${text}`);
      }
    } catch {
      // The process ended.
    }
  }

  private consume(chunk: Uint8Array): void {
    if (chunk.length === 0) return;
    const merged = new Uint8Array(this.buffer.length + chunk.length);
    merged.set(this.buffer);
    merged.set(chunk, this.buffer.length);

    let offset = 0;
    while (merged.length - offset >= 5) {
      const kind = merged[offset]!;
      const length = new DataView(
        merged.buffer,
        merged.byteOffset + offset + 1,
        4,
      ).getUint32(0, false);
      if (length > MAX_MESSAGE_BYTES) {
        this.buffer = new Uint8Array(0);
        this.log(`Helper sent an oversized message (${length} bytes)`, "error");
        return;
      }
      if (merged.length - offset - 5 < length) break;

      const payload = merged.subarray(offset + 5, offset + 5 + length);
      this.handleMessage(kind, payload);
      offset += 5 + length;
    }

    this.buffer = merged.slice(offset);
  }

  private handleMessage(kind: number, payload: Uint8Array): void {
    if (kind === 1) {
      this.handleStatus(payload);
      return;
    }
    if (kind === 2) {
      if (payload.length < 14) return;
      const frame = new Uint8Array(payload.length + 1);
      frame[0] = 2;
      frame.set(payload, 1);
      this.frame = frame;
      this.notify({ type: "frame", data: frame });
      return;
    }
    if (kind === 3) {
      try {
        const object = JSON.parse(new TextDecoder().decode(payload)) as {
          level?: string;
          message?: string;
        };
        if (object.message) {
          this.log(object.message, object.level ?? "info");
        }
      } catch {
        // Ignore malformed logs.
      }
    }
  }

  private handleStatus(payload: Uint8Array): void {
    let raw: Record<string, unknown>;
    try {
      raw = JSON.parse(new TextDecoder().decode(payload)) as Record<string, unknown>;
    } catch {
      return;
    }

    const status = this.statusValue;
    status.version = stringValue(raw.version) ?? status.version;
    status.screenRecording = raw.screenRecording === true;
    status.accessibility = raw.accessibility === true;
    status.displays = displayList(raw.displays);
    status.displayID = numberValue(raw.displayID) ?? status.displayID;
    status.fps = numberValue(raw.fps) ?? status.fps;
    status.quality = numberValue(raw.quality) ?? status.quality;
    status.maxWidth = numberValue(raw.maxWidth) ?? status.maxWidth;
    status.streaming = raw.streaming === true;
    status.error = stringValue(raw.error) ?? null;
    status.running = true;
    status.available = true;

    this.receivedStatus = true;
    this.resolveFirstStatus?.();
    this.resolveFirstStatus = null;
    this.emitStatus();
  }

  private send(message: Record<string, unknown>): void {
    if (!this.ensureChild() || !this.child) return;
    try {
      this.child.stdin.write(JSON.stringify(message) + "\n");
      void this.child.stdin.flush();
    } catch (error) {
      this.log(`Sending to the helper failed: ${String(error)}`, "error");
    }
  }

  private emitStatus(): void {
    this.notify({ type: "status", status: this.statusValue });
  }

  private log(message: string, level: string): void {
    this.notify({ type: "log", level, message });
  }

  private notify(event: RemoteEvent): void {
    for (const listener of this.listeners) {
      try {
        listener(event);
      } catch {
        // One broken socket must not stop the others.
      }
    }
  }
}

function resolveHelper(): string | null {
  const candidates: string[] = [];
  const configured = process.env.OPENCODEBAR_REMOTE_HOST?.trim();
  if (configured) candidates.push(configured);

  const root = resolve(import.meta.dir, "../..");
  candidates.push(
    join(root, ".build/debug/OpenCodeBarRemoteHost"),
    join(root, ".build/release/OpenCodeBarRemoteHost"),
    join(root, "dist/OpenCodeBarRemoteHost.app/Contents/MacOS/OpenCodeBarRemoteHost"),
  );

  const which = Bun.which("opencodebar-remote-host");
  if (which) candidates.push(which);

  for (const candidate of candidates) {
    if (!existsSync(candidate)) continue;
    try {
      accessSync(candidate, constants.X_OK);
      return candidate;
    } catch {
      continue;
    }
  }
  return null;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function displayList(value: unknown): RemoteDisplay[] {
  if (!Array.isArray(value)) return [];
  const result: RemoteDisplay[] = [];
  for (const entry of value) {
    if (!entry || typeof entry !== "object") continue;
    const object = entry as Record<string, unknown>;
    const id = numberValue(object.id);
    const width = numberValue(object.width);
    const height = numberValue(object.height);
    if (id === undefined || width === undefined || height === undefined) continue;
    result.push({
      id,
      name: stringValue(object.name) ?? `Display ${id}`,
      width,
      height,
      scale: numberValue(object.scale) ?? 1,
      primary: object.primary === true,
    });
  }
  return result;
}
