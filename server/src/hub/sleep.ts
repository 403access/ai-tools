/** A child process that keeps the machine awake until it is killed. */
export interface SleepProcess {
  kill(): void;
  exited: Promise<number>;
}

export type SpawnSleepProcess = (argv: string[]) => SleepProcess;

export interface SleepGuardOptions {
  /** Override for tests; the default starts `/usr/bin/caffeinate`. */
  spawn?: SpawnSleepProcess;
  /** Platform to check support against; defaults to the running platform. */
  platform?: NodeJS.Platform;
}

export interface SleepGuard {
  readonly supported: boolean;
  setEnabled(enabled: boolean): void;
  stop(): void;
}

const CAFFEINATE = "/usr/bin/caffeinate";

function spawnCaffeinate(argv: string[]): SleepProcess {
  return Bun.spawn({
    cmd: argv,
    stdio: ["ignore", "ignore", "ignore"],
  });
}

/**
 * Keeps macOS from idle-sleeping while the hub is running.
 *
 * `caffeinate -i` blocks idle system sleep but still lets the display turn off,
 * which is enough to keep the phone's connection alive without wasting power on
 * the screen. `-w <pid>` ties the assertion to the hub process, so a crashed
 * hub cannot leave `caffeinate` running forever.
 */
export class CaffeinateSleepGuard implements SleepGuard {
  readonly supported: boolean;

  private process: SleepProcess | null = null;
  private enabled = false;
  private readonly spawn: SpawnSleepProcess;
  private readonly log: (level: "debug" | "info" | "warn", message: string) => void;

  constructor(
    log: (level: "debug" | "info" | "warn", message: string) => void = () => {},
    options: SleepGuardOptions = {},
  ) {
    this.log = log;
    this.spawn = options.spawn ?? spawnCaffeinate;
    this.supported = (options.platform ?? process.platform) === "darwin";
  }

  setEnabled(enabled: boolean): void {
    this.enabled = enabled;
    if (!enabled || !this.supported) {
      this.stop();
      if (!enabled) this.log("info", "Allowed the Mac to sleep");
      return;
    }
    if (this.process) return;

    try {
      const child = this.spawn([CAFFEINATE, "-i", "-w", String(process.pid)]);
      this.process = child;
      child.exited
        .then((code) => {
          if (this.process === child) this.process = null;
          if (this.enabled && code !== 0) {
            this.log("warn", `caffeinate exited with status ${code}`);
          }
        })
        .catch(() => {
          if (this.process === child) this.process = null;
        });
      this.log("info", "Preventing the Mac from idle sleeping");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.log("warn", `Could not prevent sleep: ${message}`);
    }
  }

  stop(): void {
    const child = this.process;
    this.process = null;
    if (!child) return;
    try {
      child.kill();
    } catch {
      // Already gone.
    }
  }
}
