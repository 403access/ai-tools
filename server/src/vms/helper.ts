import { accessSync, constants, closeSync, existsSync, openSync, readFileSync } from "node:fs";
import { createConnection, type Socket } from "node:net";
import { dirname, join, resolve } from "node:path";
import { findExecutable } from "../system/commands.ts";

export interface HelperStatus {
  state:
    | "stopped"
    | "starting"
    | "running"
    | "paused"
    | "pausing"
    | "resuming"
    | "stopping"
    | "error";
  pid: number;
  startedAt?: number;
  error?: string | null;
}

export interface HelperRuntime {
  pid: number;
  version?: string;
  /** Loopback port for the JSON control channel. */
  controlPort: number;
  /** Loopback port for the raw serial console. */
  serialPort: number;
  startedAt: number;
}

export class VMHelperError extends Error {
  constructor(message: string, readonly status = 502) {
    super(message);
    this.name = "VMHelperError";
  }
}

function executable(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Finds the Swift helper that owns Virtualization.framework. The hub is usually
 * started from the repository root, so the SwiftPM build directory is the first
 * place to look; a distributed build can set OPENCODEBAR_VZ_HELPER.
 */
export function findVZHelper(env: NodeJS.ProcessEnv = process.env): string | null {
  const override = env.OPENCODEBAR_VZ_HELPER?.trim();
  if (override && executable(override)) return override;

  const roots = new Set<string>([
    process.cwd(),
    resolve(import.meta.dir, "../../.."),
    resolve(import.meta.dir, "../.."),
  ]);
  for (const root of roots) {
    // Prefer the debug helper because `make vz-helper` signs that build. A
    // release binary from `make app` is not signed automatically.
    for (const relative of [
      "dist/OpenCodeBarVZ",
      ".build/debug/OpenCodeBarVZ",
      ".build/release/OpenCodeBarVZ",
    ]) {
      const candidate = join(root, relative);
      if (executable(candidate)) return candidate;
    }
  }

  return findExecutable("OpenCodeBarVZ") ?? null;
}

export function readRuntime(path: string): HelperRuntime | null {
  try {
    const value: unknown = JSON.parse(readFileSync(path, "utf8"));
    if (!value || typeof value !== "object") return null;
    const record = value as Record<string, unknown>;
    if (
      typeof record.pid !== "number" ||
      typeof record.controlPort !== "number" ||
      typeof record.serialPort !== "number"
    ) {
      return null;
    }
    return {
      pid: record.pid,
      version: typeof record.version === "string" ? record.version : undefined,
      controlPort: record.controlPort,
      serialPort: record.serialPort,
      startedAt: typeof record.startedAt === "number" ? record.startedAt : Date.now(),
    };
  } catch {
    return null;
  }
}

export function processAlive(pid: number): boolean {
  if (!Number.isFinite(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export interface SpawnedHelper {
  pid: number;
}

/**
 * Starts a helper process for one VM and detaches it, so the guest keeps
 * running when the hub restarts. The helper writes its own runtime.json once
 * its control socket is listening.
 */
export function spawnHelper(
  helperPath: string,
  configPath: string,
  logPath: string,
): SpawnedHelper {
  const fd = openSync(logPath, "a", 0o600);
  try {
    const proc = Bun.spawn([helperPath, "run", "--config", configPath], {
      cwd: dirname(configPath),
      stdin: "ignore",
      stdout: fd,
      stderr: fd,
      env: { ...process.env },
      detached: true,
    });
    proc.unref();
    return { pid: proc.pid };
  } finally {
    closeSync(fd);
  }
}

interface PendingRequest {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: ReturnType<typeof setTimeout>;
}

/**
 * A tiny JSON-lines client for the helper's Unix-domain control socket. One
 * request is in flight at a time, which matches how the hub drives a VM.
 */
export class HelperClient {
  private nextID = 1;
  private buffer = "";
  private pending: PendingRequest | null = null;

  private constructor(private readonly socket: Socket) {
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => this.onData(chunk));
    socket.on("error", (error) => this.fail(error));
    socket.on("close", () => this.fail(new VMHelperError("The VM helper closed the connection")));
  }

  static async open(port: number, timeoutMs = 2_000): Promise<HelperClient> {
    const socket = createConnection({ host: "127.0.0.1", port });
    const client = new HelperClient(socket);
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => {
        socket.destroy();
        reject(new VMHelperError("Timed out connecting to the VM helper"));
      }, timeoutMs);
      socket.once("connect", () => {
        clearTimeout(timer);
        resolve();
      });
      socket.once("error", (error) => {
        clearTimeout(timer);
        reject(new VMHelperError(`Could not reach the VM helper: ${error.message}`));
      });
    });
    return client;
  }

  request<T = unknown>(op: string, params: Record<string, unknown> = {}, timeoutMs = 15_000): Promise<T> {
    if (this.pending) {
      return Promise.reject(new VMHelperError("The VM helper is already handling a request"));
    }
    const id = this.nextID++;
    const payload = JSON.stringify({ id, op, ...params });
    return new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending = null;
        this.socket.destroy();
        reject(new VMHelperError(`The VM helper did not answer \`${op}\` in time`));
      }, timeoutMs);
      this.pending = {
        resolve: resolve as (value: unknown) => void,
        reject,
        timer,
      };
      this.socket.write(`${payload}\n`);
    });
  }

  close(): void {
    this.pending?.timer && clearTimeout(this.pending.timer);
    this.pending = null;
    this.socket.destroy();
  }

  private onData(chunk: string): void {
    this.buffer += chunk;
    let newline = this.buffer.indexOf("\n");
    while (newline >= 0) {
      const line = this.buffer.slice(0, newline).trim();
      this.buffer = this.buffer.slice(newline + 1);
      if (line) this.handleLine(line);
      newline = this.buffer.indexOf("\n");
    }
  }

  private handleLine(line: string): void {
    let message: Record<string, unknown>;
    try {
      message = JSON.parse(line) as Record<string, unknown>;
    } catch {
      return;
    }
    const pending = this.pending;
    if (!pending) return;
    this.pending = null;
    clearTimeout(pending.timer);
    if (message.ok === false) {
      pending.reject(new VMHelperError(String(message.error ?? "The VM helper failed"), 502));
    } else {
      pending.resolve(message.result);
    }
  }

  private fail(error: Error): void {
    const pending = this.pending;
    if (!pending) return;
    this.pending = null;
    clearTimeout(pending.timer);
    pending.reject(error instanceof VMHelperError ? error : new VMHelperError(error.message));
  }
}

export async function helperStatus(port: number, timeoutMs = 2_000): Promise<HelperStatus | null> {
  let client: HelperClient | null = null;
  try {
    client = await HelperClient.open(port, timeoutMs);
    return await client.request<HelperStatus>("status", {}, timeoutMs);
  } catch {
    return null;
  } finally {
    client?.close();
  }
}

/**
 * Waits for the helper to write its runtime record and answer on the control
 * port. The record is written only after both listeners are accepting, so this
 * avoids a race between spawning and the first request.
 */
export async function waitForHelperRuntime(
  runtimePath: string,
  timeoutMs = 10_000,
): Promise<HelperRuntime> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const runtime = readRuntime(runtimePath);
    if (runtime) {
      const status = await helperStatus(runtime.controlPort, 500);
      if (status) return runtime;
    }
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new VMHelperError("The VM helper did not start. Check the VM's serial log for details.");
}

export async function startHelperVM(port: number): Promise<HelperStatus> {
  const client = await HelperClient.open(port, 3_000);
  try {
    return await client.request<HelperStatus>("start", {}, 90_000);
  } finally {
    client.close();
  }
}

export async function stopHelperVM(
  port: number,
  options: { force?: boolean; timeoutMs?: number } = {},
): Promise<HelperStatus> {
  const client = await HelperClient.open(port, 3_000);
  try {
    return await client.request<HelperStatus>(
      "stop",
      { force: options.force === true },
      options.timeoutMs ?? 60_000,
    );
  } finally {
    client.close();
  }
}

export async function pauseHelperVM(port: number): Promise<HelperStatus> {
  const client = await HelperClient.open(port, 3_000);
  try {
    return await client.request<HelperStatus>("pause", {}, 30_000);
  } finally {
    client.close();
  }
}

export async function resumeHelperVM(port: number): Promise<HelperStatus> {
  const client = await HelperClient.open(port, 3_000);
  try {
    return await client.request<HelperStatus>("resume", {}, 30_000);
  } finally {
    client.close();
  }
}
