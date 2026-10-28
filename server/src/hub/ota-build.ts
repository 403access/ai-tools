import { existsSync } from "node:fs";
import { resolve } from "node:path";
import type { OtaArtifact, OtaBuildStatus } from "../types.ts";
import type { OtaStore } from "./ota.ts";

export class OtaBuildBusyError extends Error {
  constructor() {
    super("A build is already running");
  }
}

export class OtaBuildUnavailableError extends Error {
  constructor() {
    super("OTA builds need the source checkout; run `make mobile-ota` instead");
  }
}

export interface OtaBuilderOptions {
  store: OtaStore;
  /** Tests can replace the xcodebuild run with a stub. */
  build?: () => Promise<void>;
  scriptPath?: string;
  repoRoot?: string;
  onPublished?: (artifact: OtaArtifact) => void;
}

/**
 * Runs one OTA archive/export at a time on the hub host and publishes the
 * result into the store. The macOS app polls `snapshot()` for progress.
 */
export class OtaBuilder {
  private status: OtaBuildStatus = { state: "idle", log: [] };
  private running = false;
  private resultID: string | null = null;
  private installed = false;
  private device: string | undefined;

  constructor(private readonly options: OtaBuilderOptions) {}

  snapshot(): OtaBuildStatus {
    return {
      ...this.status,
      log: [...this.status.log],
      ...(this.status.artifact ? { artifact: { ...this.status.artifact } } : {}),
    };
  }

  get busy(): boolean {
    return this.running;
  }

  start(): OtaBuildStatus {
    if (this.running) throw new OtaBuildBusyError();
    const script = this.scriptPath();
    if (!this.options.build && !existsSync(script)) {
      throw new OtaBuildUnavailableError();
    }

    this.running = true;
    this.resultID = null;
    this.installed = false;
    this.device = undefined;
    this.status = {
      state: "running",
      startedAt: Date.now(),
      log: [`Building ${this.options.store.root}`],
    };
    void this.run(script);
    return this.snapshot();
  }

  private async run(script: string): Promise<void> {
    try {
      this.options.store.prepare();
      if (this.options.build) {
        await this.options.build();
      } else {
        await this.runScript(script);
      }
      this.options.store.prune();
      const artifact =
        (this.resultID ? this.options.store.get(this.resultID) : null) ??
        this.options.store.latest();
      if (!artifact) throw new Error("The build finished without a publishable app");

      this.status = {
        state: "succeeded",
        startedAt: this.status.startedAt,
        finishedAt: Date.now(),
        log: this.status.log,
        artifact,
        installed: this.installed,
        ...(this.device ? { device: this.device } : {}),
      };
      this.options.onPublished?.(artifact);
    } catch (caught) {
      const message = caught instanceof Error ? caught.message : String(caught);
      this.status = {
        state: "failed",
        startedAt: this.status.startedAt,
        finishedAt: Date.now(),
        log: this.status.log,
        error: message,
      };
    } finally {
      this.running = false;
    }
  }

  private async runScript(script: string): Promise<void> {
    const repoRoot = this.options.repoRoot ?? resolve(import.meta.dir, "../../..");
    const proc = Bun.spawn({
      // `--install` tries the phone over USB or the local network and falls
      // back to the published link, which works from any network.
      cmd: ["bash", script, "--install", "--json", "--no-qr", "--out", this.options.store.root],
      cwd: repoRoot,
      env: {
        ...process.env,
        // A hub started from the app or launchd may not inherit Homebrew's
        // paths, which the script needs for xcodegen and xcrun.
        PATH: [
          "/opt/homebrew/bin",
          "/usr/local/bin",
          process.env.PATH ?? "/usr/bin:/bin:/usr/sbin:/sbin",
        ].join(":"),
      },
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });

    const pumps = [this.pump(proc.stdout), this.pump(proc.stderr)];
    const exitCode = await proc.exited;
    await Promise.all(pumps);

    if (exitCode !== 0) {
      const tail = this.status.log.slice(-3).join(" · ");
      throw new Error(tail || `The build failed (exit ${exitCode})`);
    }
  }

  private async pump(stream: ReadableStream<Uint8Array> | undefined): Promise<void> {
    if (!stream) return;
    const reader = stream.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buffer += decoder.decode(value, { stream: true });
        let newline = buffer.indexOf("\n");
        while (newline >= 0) {
          this.line(buffer.slice(0, newline));
          buffer = buffer.slice(newline + 1);
          newline = buffer.indexOf("\n");
        }
      }
      if (buffer.trim()) this.line(buffer);
    } finally {
      reader.releaseLock();
    }
  }

  private line(raw: string): void {
    const line = raw.trim();
    if (!line) return;
    if (line.startsWith("OTA_RESULT ")) {
      try {
        const parsed = JSON.parse(line.slice("OTA_RESULT ".length)) as {
          id?: unknown;
          installed?: unknown;
          device?: unknown;
        };
        if (typeof parsed.id === "string") this.resultID = parsed.id;
        if (parsed.installed === true) this.installed = true;
        if (typeof parsed.device === "string" && parsed.device) this.device = parsed.device;
      } catch {
        // The final JSON is only a hint; the store is authoritative.
      }
      return;
    }
    this.status.log.push(line.slice(0, 400));
    if (this.status.log.length > 120) this.status.log.shift();
  }

  private scriptPath(): string {
    if (this.options.scriptPath) return this.options.scriptPath;
    const repoRoot = this.options.repoRoot ?? resolve(import.meta.dir, "../../..");
    return resolve(repoRoot, "Scripts/deploy-ota.sh");
  }
}
