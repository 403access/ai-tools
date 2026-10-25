import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  realpathSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { homedir, userInfo } from "node:os";
import { join, resolve } from "node:path";
import type { CommandRunner } from "../system/types.ts";
import { defaultRunner } from "../system/commands.ts";
import {
  findVZHelper,
  helperStatus,
  pauseHelperVM,
  processAlive,
  readRuntime,
  resumeHelperVM,
  spawnHelper,
  startHelperVM,
  stopHelperVM,
  waitForHelperRuntime,
  VMHelperError,
  type HelperStatus,
} from "./helper.ts";
import { appendLog, createLogWriter, readLogTail, resetLog } from "./logs.ts";
import {
  findGuestAddress,
  collectMetrics,
  guestMetrics,
  runGuest,
  scpToGuest,
  waitForGuestSSH,
  shellQuote,
} from "./metrics.ts";
import {
  IMAGE_ATTRIBUTE,
  VMValidationError,
  guestHostname,
  normalizeChannel,
  normalizePackages,
  renderConfiguration,
  renderFlake,
  stateVersionFor,
  validateVMName,
} from "./nixos.ts";
import {
  clampCPU,
  clampDisk,
  clampMemory,
  preflight,
} from "./preflight.ts";
import {
  VMStore,
  hostnameFor,
  newMACAddress,
  newVMID,
  vmRoot,
} from "./store.ts";
import type {
  VMAction,
  VMCapabilities,
  VMCreateInput,
  VMLog,
  VMLogType,
  VMMetrics,
  VMSetupJob,
  VMSetupLogFile,
  VMSetupLogResult,
  VMSetupStep,
  VMStatus,
  VMUpdateInput,
  VirtualMachine,
  VirtualMachineStore,
} from "./types.ts";

const METRICS_TTL_MS = 5_000;
const RECONCILE_TTL_MS = 1_500;
const CAPABILITIES_TTL_MS = 30_000;
const BOOT_TIMEOUT_MS = 150_000;
const ANSI_ESCAPE = /\u001b\[[0-?]*[ -/]*[@-~]/g;

export interface VMServiceOptions {
  store?: VMStore;
  root?: string;
  runner?: CommandRunner;
  env?: NodeJS.ProcessEnv;
  now?: () => number;
  /** Repository root for `make vz-helper`; derived from this module by default. */
  repoRoot?: string;
}

interface CachedMetrics {
  at: number;
  value: VMMetrics;
}

/**
 * Owns VM definitions, image builds, helper processes and package updates.
 *
 * Long-running work (Nix builds, `nixos-rebuild switch`) is streamed to a log
 * and tracked in memory so an HTTP request never has to wait for it. The helper
 * process is detached: guests keep running when the hub restarts, and the next
 * request re-adopts them from their control socket.
 */
export class VirtualMachineService implements VirtualMachineStore {
  readonly store: VMStore;
  private readonly runner: CommandRunner;
  private readonly env: NodeJS.ProcessEnv;
  private readonly now: () => number;
  private readonly repoRoot: string;

  private setupJob: VMSetupJob | null = null;
  private setupProcess: ReturnType<typeof Bun.spawn> | null = null;
  /** Terminal.app tab running the Nix installer, when the job uses Terminal. */
  private setupTerminalWindow: number | null = null;

  private readonly builds = new Set<string>();
  private readonly applies = new Set<string>();
  private readonly bootWaiters = new Set<string>();
  private readonly deleted = new Set<string>();

  private readonly reconciledAt = new Map<string, number>();
  private readonly metricsCache = new Map<string, CachedMetrics>();
  private readonly probes = new Map<string, Promise<VMMetrics>>();

  private capabilitiesCache: { at: number; value: VMCapabilities } | null = null;
  private capabilitiesInFlight: Promise<VMCapabilities> | null = null;

  constructor(options: VMServiceOptions = {}) {
    this.store = options.store ?? new VMStore({ root: options.root ?? vmRoot(options.env) });
    this.runner = options.runner ?? defaultRunner;
    this.env = options.env ?? process.env;
    this.now = options.now ?? Date.now;
    this.repoRoot = resolve(options.repoRoot ?? join(import.meta.dir, "../../.."));
  }

  // MARK: - Reading

  async capabilities(): Promise<VMCapabilities> {
    const now = this.now();
    if (this.capabilitiesCache && now - this.capabilitiesCache.at < CAPABILITIES_TTL_MS) {
      return this.capabilitiesCache.value;
    }
    if (this.capabilitiesInFlight) return this.capabilitiesInFlight;

    this.capabilitiesInFlight = preflight({
      runner: this.runner,
      env: this.env,
      storageDir: this.store.root,
    })
      .then((result) => {
        this.capabilitiesCache = { at: this.now(), value: result.capabilities };
        return result.capabilities;
      })
      .finally(() => {
        this.capabilitiesInFlight = null;
      });
    return this.capabilitiesInFlight;
  }

  async list(): Promise<VirtualMachine[]> {
    const vms = this.store.list();
    await Promise.all(vms.map((vm) => this.reconcile(vm)));
    return vms;
  }

  async get(id: string, refresh = false): Promise<VirtualMachine | null> {
    const vm = this.store.read(id);
    if (!vm) return null;
    await this.reconcile(vm);
    if (this.deleted.has(id)) return null;

    if (vm.status !== "building") {
      const cached = this.metricsCache.get(id);
      if (refresh || !cached || this.now() - cached.at > METRICS_TTL_MS) {
        const metrics = await this.refreshMetrics(vm);
        vm.metrics = metrics;
        if (metrics.guest?.reachable) {
          vm.network.reachable = true;
          if (vm.progress?.phase === "booting") vm.progress = null;
        } else if (metrics.guest?.error) {
          vm.network.reachable = false;
        }
        this.save(vm);
      } else {
        vm.metrics = cached.value;
      }
    }
    return vm;
  }

  // MARK: - Creation

  async create(input: VMCreateInput): Promise<VirtualMachine> {
    const capabilities = await this.capabilities();
    if (!capabilities.supported) {
      throw new VMValidationError("Virtual machines require an Apple silicon Mac", 501);
    }
    if (!capabilities.helperAvailable) {
      throw new VMValidationError(
        "The OpenCodeBarVZ helper is missing. Run `make vz-helper` and restart the hub.",
        503,
      );
    }

    const name = validateVMName(input.name);
    const channel = normalizeChannel(input.channel);
    const existing = this.store.list();
    const id = newVMID();
    const hostname = hostnameFor(id);
    const packages = normalizePackages(input.packages);
    const cpuCount = clampCPU(input.cpuCount ?? capabilities.defaultCPU, capabilities.maxCPU);
    const memoryMB = clampMemory(input.memoryMB ?? capabilities.defaultMemoryMB, capabilities.maxMemoryMB);
    const diskGB = clampDisk(input.diskGB);

    const paths = this.store.createLayout(id);
    const publicKey = await this.createSSHKey(id, paths.directory).catch((error) => {
      this.store.remove(id);
      throw error;
    });

    const vm: VirtualMachine = {
      id,
      name,
      distro: "nixos",
      channel,
      stateVersion: stateVersionFor(channel),
      arch: "aarch64",
      status: "building",
      createdAt: this.now(),
      updatedAt: this.now(),
      cpuCount,
      memoryMB,
      diskGB,
      packages,
      pendingPackages: [],
      lastError: null,
      progress: {
        phase: "queued",
        message: "Waiting to build the NixOS image",
        startedAt: this.now(),
      },
      ssh: {
        user: "opencodebar",
        keyPath: join(paths.directory, "ssh", "id_ed25519"),
        publicKey,
      },
      network: {
        mac: newMACAddress(existing),
        ip: null,
        reachable: false,
      },
      paths,
      metrics: null,
    };

    this.writeSources(vm);
    vm.updatedAt = this.now();
    this.store.write(vm);
    this.startBuild(vm, input.autostart !== false);
    return vm;
  }

  // MARK: - Control

  async control(id: string, action: VMAction, force = false): Promise<VirtualMachine> {
    const vm = this.requireVM(id);
    if (this.deleted.has(id)) throw new VMValidationError("Virtual machine not found", 404);

    switch (action) {
      case "start":
        return this.start(vm);
      case "stop":
        return this.stop(vm, force);
      case "restart":
        await this.stop(vm, force);
        return this.start(this.requireVM(id));
      case "pause":
        return this.pause(vm);
      case "resume":
        return this.resume(vm);
      case "rebuild":
        return this.rebuild(vm, force);
      case "apply":
        return this.applyNow(vm);
      default:
        throw new VMValidationError(`Unknown VM action: ${String(action)}`);
    }
  }

  async update(id: string, input: VMUpdateInput): Promise<VirtualMachine> {
    const vm = this.requireVM(id);
    if (this.builds.has(id)) {
      throw new VMValidationError("Wait for the image build to finish before editing this VM", 409);
    }
    if (input.name !== undefined) vm.name = validateVMName(input.name);
    if (input.cpuCount !== undefined || input.memoryMB !== undefined) {
      if (vm.status === "running" || vm.status === "starting" || vm.status === "paused") {
        throw new VMValidationError("Stop the VM before changing its CPU or memory", 409);
      }
      const capabilities = await this.capabilities();
      if (input.cpuCount !== undefined) vm.cpuCount = clampCPU(input.cpuCount, capabilities.maxCPU);
      if (input.memoryMB !== undefined) vm.memoryMB = clampMemory(input.memoryMB, capabilities.maxMemoryMB);
    }
    if (input.packages !== undefined) {
      const packages = normalizePackages(input.packages);
      const changed = !sameStrings(packages, vm.packages);
      vm.packages = packages;
      if (changed) {
        if (vm.status === "running") {
          vm.pendingPackages = packages;
          this.beginApply(vm);
        } else if (vm.status === "starting") {
          vm.pendingPackages = packages;
        } else if (vm.status === "building") {
          // The build reads the updated configuration from disk.
          vm.pendingPackages = [];
        } else {
          vm.pendingPackages = packages;
        }
      }
    }
    this.writeSources(vm);
    this.save(vm);
    return vm;
  }

  async remove(id: string, force = false): Promise<void> {
    const vm = this.requireVM(id);
    if (this.builds.has(id) && !force) {
      throw new VMValidationError("The image is still building. Stop it or pass force=1.", 409);
    }
    if ((vm.status === "running" || vm.status === "starting" || vm.status === "paused") && !force) {
      throw new VMValidationError("Stop the virtual machine before deleting it", 409);
    }
    if (force && vm.status !== "stopped" && vm.status !== "building") {
      await this.stop(vm, true).catch(() => undefined);
    }
    await this.killHelper(vm);
    this.deleted.add(id);
    this.metricsCache.delete(id);
    this.reconciledAt.delete(id);
    this.store.remove(id);
  }

  async log(id: string, type: VMLogType, tail = 240): Promise<VMLog> {
    const vm = this.requireVM(id);
    const path = logPath(vm, type);
    const result = readLogTail(path, Math.min(Math.max(tail, 1), 2_000));
    return {
      type,
      path,
      lines: result.lines,
      bytes: result.bytes,
      truncated: result.truncated,
    };
  }

  async consoleTarget(id: string): Promise<{ vmID: string; host: string; port: number }> {
    const vm = this.requireVM(id);
    await this.reconcile(vm);
    if (vm.status === "stopped" || vm.status === "error" || vm.status === "building") {
      throw new VMValidationError("Start the virtual machine to open its serial console", 409);
    }
    const runtime = readRuntime(vm.paths.runtime);
    if (!runtime || !processAlive(runtime.pid)) {
      throw new VMValidationError("The serial console is not ready yet", 503);
    }
    return { vmID: id, host: "127.0.0.1", port: runtime.serialPort };
  }

  // MARK: - Host setup

  async setupStatus(): Promise<VMSetupJob | null> {
    if (!this.setupJob) return null;
    return { ...this.setupJob, log: this.readSetupLog(this.setupJob) };
  }

  /** Stored setup logs, including rotated runs, newest first. */
  async setupLogs(): Promise<VMSetupLogFile[]> {
    const directory = join(this.store.root, "setup");
    if (!existsSync(directory)) return [];
    const entries: VMSetupLogFile[] = [];
    for (const name of readdirSync(directory)) {
      if (!name.endsWith(".log")) continue;
      const step: VMSetupStep | null =
        name === "nix.log" || name.startsWith("nix-")
          ? "nix"
          : name === "helper.log" || name.startsWith("helper-")
            ? "helper"
            : name === "builder.log" || name.startsWith("builder-")
              ? "builder"
              : null;
      if (!step) continue;
      const path = join(directory, name);
      try {
        const stats = statSync(path);
        if (!stats.isFile()) continue;
        entries.push({ step, path, bytes: stats.size, modified: stats.mtimeMs });
      } catch {
        // A log can disappear while the directory is being cleaned up.
      }
    }
    return entries.sort((a, b) => b.modified - a.modified);
  }

  async setupLog(step: VMSetupStep, tail = 240): Promise<VMSetupLogResult> {
    const directory = join(this.store.root, "setup");
    let path = join(directory, `${step}.log`);
    if (!existsSync(path)) {
      const newest = (await this.setupLogs()).find((entry) => entry.step === step);
      if (!newest) {
        return { step, path, lines: [], bytes: 0, truncated: false };
      }
      path = newest.path;
    }
    const result = readLogTail(path, Math.min(Math.max(tail, 1), 2_000));
    return {
      step,
      path,
      lines: result.lines.map((line) => line.replace(ANSI_ESCAPE, "")),
      bytes: result.bytes,
      truncated: result.truncated,
    };
  }

  private pruneSetupLogs(step: VMSetupStep, keep: number): void {
    const directory = join(this.store.root, "setup");
    if (!existsSync(directory)) return;
    const prefix = `${step}-`;
    const files = readdirSync(directory)
      .filter((name) => name.startsWith(prefix) && name.endsWith(".log"))
      .map((name) => {
        const path = join(directory, name);
        return { path, mtime: statSync(path).mtimeMs };
      })
      .sort((a, b) => b.mtime - a.mtime);
    for (const file of files.slice(keep)) {
      rmSync(file.path, { force: true });
    }
  }

  async startSetup(step: VMSetupStep): Promise<VMSetupJob> {
    if (this.setupJob?.status === "running") {
      throw new VMValidationError("A host setup job is already running", 409);
    }
    if (step !== "nix" && step !== "helper") {
      throw new VMValidationError("Unknown host setup step", 400);
    }

    const capabilities = await this.capabilities();
    if (step === "nix" && capabilities.nixAvailable) {
      throw new VMValidationError("Nix is already installed", 409);
    }
    if (step === "helper" && capabilities.helperAvailable && capabilities.helperEntitled) {
      throw new VMValidationError("The VM helper is already built and signed", 409);
    }

    const directory = join(this.store.root, "setup");
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    chmodSync(directory, 0o700);
    const logPath = join(directory, `${step}.log`);
    // Preserve the previous run before starting a new one. The UI can always
    // read the latest `step.log`; rotated copies keep the installer history.
    if (existsSync(logPath) && statSync(logPath).size > 0) {
      const stamp = new Date(this.now()).toISOString().replace(/[:.]/g, "-");
      renameSync(logPath, join(directory, `${step}-${stamp}.log`));
      this.pruneSetupLogs(step, 10);
    }
    // Keep the log readable by the hub user while the directory stays
    // owner-only. The Nix installer writes to it from Terminal.
    writeFileSync(logPath, "", { mode: 0o644 });
    chmodSync(logPath, 0o644);

    const job: VMSetupJob = {
      step,
      status: "running",
      command:
        step === "nix"
          ? "curl -fsSL https://nixos.org/nix/install | sh -s -- --yes"
          : "make vz-helper",
      requiresAdmin: step === "nix",
      startedAt: this.now(),
      finishedAt: null,
      exitCode: null,
      error: null,
      log: { path: logPath, lines: [], bytes: 0, truncated: false },
    };
    this.setupJob = job;
    this.setupTerminalWindow = null;

    void this.runSetup(job).catch((error) => {
      job.status = "failed";
      job.finishedAt = this.now();
      job.error = messageFor(error);
      this.setupJob = job;
    });
    return (await this.setupStatus())!;
  }

  async cancelSetup(): Promise<VMSetupJob | null> {
    const job = this.setupJob;
    if (!job || job.status !== "running") return this.setupStatus();
    job.status = "cancelled";
    job.finishedAt = this.now();
    job.error = "Cancelled";
    const window = this.setupTerminalWindow;
    this.setupTerminalWindow = null;
    if (window !== null) {
      // The installer runs inside Terminal.app, so close its dedicated window
      // rather than trying to signal a process the hub no longer owns.
      const applescript =
        `tell application "Terminal" to close (every window whose id is ${window}) saving no`;
      try {
        Bun.spawn(["/usr/bin/osascript", "-e", applescript], {
          stdin: "ignore",
          stdout: "ignore",
          stderr: "ignore",
        });
      } catch {
        // Terminal may already be closed.
      }
    }
    const proc = this.setupProcess;
    this.setupProcess = null;
    if (proc) {
      try {
        process.kill(-proc.pid, "SIGTERM");
      } catch {
        try {
          proc.kill();
        } catch {
          // Already exited.
        }
      }
    }
    return this.setupStatus();
  }

  private readSetupLog(job: VMSetupJob): VMSetupJob["log"] {
    const tail = readLogTail(job.log.path, 240, 128 * 1024);
    return {
      path: job.log.path,
      lines: tail.lines.map((line) => line.replace(ANSI_ESCAPE, "")),
      bytes: tail.bytes,
      truncated: tail.truncated,
    };
  }

  private async runSetup(job: VMSetupJob): Promise<void> {
    if (job.step === "nix") {
      await this.runNixInTerminal(job);
    } else {
      await this.runHelperBuild(job);
    }
  }

  /**
   * Runs the official installer inside Terminal.app as the logged-in user.
   *
   * The installer's `vifs` step is blocked when the hub spawns it directly:
   * macOS 27 marks /etc SIP-restricted, and a non-GUI process cannot create
   * /etc/fstab. A GUI Terminal session is the documented workaround. The script
   * tees the installer output into the hub's setup log, so the phone still sees
   * live progress, and writes an exit code for the hub to poll.
   */
  private async runNixInTerminal(job: VMSetupJob): Promise<void> {
    const directory = join(this.store.root, "setup");
    const scriptPath = join(directory, "run-nix-terminal.sh");
    const statusPath = join(directory, "nix.status");
    const logPath = job.log.path;
    rmSync(statusPath, { force: true });
    const user = userInfo().username;
    const home = homedir();
    const script = `#!/bin/sh
set -u
export HOME=${shellQuote(home)}
export USER=${shellQuote(user)}
export LOGNAME=${shellQuote(user)}
export TERM=xterm-256color
umask 0022
{
  /bin/sh -c ${shellQuote(job.command)}
  echo $? > ${shellQuote(statusPath)}
} 2>&1 | /usr/bin/tee -a ${shellQuote(logPath)}
`;
    writeFileSync(scriptPath, script, { mode: 0o700 });
    chmodSync(scriptPath, 0o700);

    const escaped = scriptPath.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    // A dedicated window gives us a stable window id for Cancel. Terminal's
    // tab objects do not expose `id` on current macOS versions.
    const applescript = `tell application "Terminal"
  activate
  set w to make new window
  do script "/bin/sh " & quoted form of "${escaped}" in w
  return id of w
end tell`;
    const proc = Bun.spawn(["/usr/bin/osascript", "-e", applescript], {
      cwd: directory,
      env: { ...this.env },
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    });
    this.setupProcess = proc;
    let stdout = "";
    let stderr = "";
    let launchCode = 0;
    try {
      [stdout, stderr, launchCode] = await Promise.all([
        readTextStream(proc.stdout),
        readTextStream(proc.stderr),
        proc.exited,
      ]);
    } finally {
      if (this.setupProcess === proc) this.setupProcess = null;
    }
    if (launchCode !== 0) {
      throw new VMValidationError(
        stderr.trim() ||
          "Could not open Terminal on the Mac. Allow OpenCodeBar to control Terminal, or run the command manually.",
        500,
      );
    }
    const tab = Number.parseInt(stdout.trim(), 10);
    if (Number.isFinite(tab)) this.setupTerminalWindow = tab;
    appendLog(
      logPath,
      `\n# Terminal opened on the Mac. Enter the administrator password there.\n`,
    );

    const deadline = this.now() + 60 * 60_000;
    while (job.status === "running" && this.now() < deadline) {
      if (existsSync(statusPath)) {
        const raw = readFileSync(statusPath, "utf8").trim();
        const exitCode = Number.parseInt(raw, 10);
        job.exitCode = Number.isFinite(exitCode) ? exitCode : 1;
        job.finishedAt = this.now();
        if (job.exitCode === 0 && existsSync("/nix/var/nix/profiles/default/bin/nix")) {
          job.status = "succeeded";
          this.capabilitiesCache = null;
        } else {
          job.status = "failed";
          job.error =
            job.exitCode === 0
              ? "The installer finished, but the Nix binary was not found."
              : lastLogLines(logPath, 6).replace(ANSI_ESCAPE, "") ||
                `Installer exited with code ${job.exitCode}`;
        }
        this.setupJob = job;
        return;
      }
      await new Promise((resolve) => setTimeout(resolve, 1_000));
    }
    if (job.status === "running") {
      job.status = "failed";
      job.finishedAt = this.now();
      job.error = "Timed out waiting for the installer in Terminal.";
      this.setupJob = job;
    }
  }

  private async runHelperBuild(job: VMSetupJob): Promise<void> {
    const logPath = job.log.path;
    const writer = createLogWriter(logPath);
    const proc = Bun.spawn(["/usr/bin/make", "vz-helper"], {
      cwd: this.repoRoot,
      env: { ...this.env },
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
      detached: true,
    });
    this.setupProcess = proc;
    const pumps = [pump(proc.stdout, writer), pump(proc.stderr, writer)];
    const exitCode = await proc.exited;
    await Promise.allSettled(pumps);
    if (this.setupProcess === proc) this.setupProcess = null;
    if (job.status !== "running") return;

    job.exitCode = exitCode;
    job.finishedAt = this.now();
    if (exitCode === 0) {
      job.status = "succeeded";
      this.capabilitiesCache = null;
    } else {
      job.status = "failed";
      job.error =
        lastLogLines(logPath, 6).replace(ANSI_ESCAPE, "") ||
        `Helper build exited with code ${exitCode}`;
    }
    this.setupJob = job;
  }

  // MARK: - Lifecycle

  private async start(vm: VirtualMachine): Promise<VirtualMachine> {
    if (this.builds.has(vm.id)) {
      throw new VMValidationError("The image is still building", 409);
    }
    if (vm.status === "running") return this.get(vm.id) as Promise<VirtualMachine>;
    if (vm.status === "starting") return vm;
    if (vm.status === "stopping") {
      throw new VMValidationError("Wait for the virtual machine to stop first", 409);
    }
    if (!existsSync(vm.paths.disk)) {
      throw new VMValidationError(
        "This VM has no disk image yet. Use rebuild to build it from the NixOS configuration.",
        409,
      );
    }
    const helper = findVZHelper(this.env);
    if (!helper) {
      throw new VMValidationError(
        "The OpenCodeBarVZ helper is missing. Run `make vz-helper`.",
        503,
      );
    }

    vm.status = "starting";
    vm.lastError = null;
    vm.network.ip = null;
    vm.network.reachable = false;
    vm.metrics = null;
    vm.progress = { phase: "starting", message: "Starting Virtualization.framework", startedAt: this.now() };
    this.save(vm);

    try {
      this.clearRuntime(vm);
      this.writeHelperConfig(vm);
      spawnHelper(helper, join(vm.paths.directory, "helper.json"), join(vm.paths.directory, "helper.log"));
      const runtime = await waitForHelperRuntime(vm.paths.runtime, 10_000);
      const status = await startHelperVM(runtime.controlPort);
      vm.status = status.state === "running" ? "running" : "starting";
      vm.startedAt = status.startedAt ?? this.now();
      vm.lastBootAt = vm.startedAt;
      vm.progress = {
        phase: "booting",
        message: "Waiting for NixOS to boot and publish its address",
        startedAt: this.now(),
      };
      this.save(vm);
      await this.discoverAddress(vm, 5_000);
      this.save(vm);
      this.watchBoot(vm.id);
      return vm;
    } catch (caught) {
      const message = messageFor(caught);
      await this.killHelper(vm).catch(() => undefined);
      vm.status = "error";
      vm.lastError = message;
      vm.progress = null;
      this.save(vm);
      throw new VMHelperError(message);
    }
  }

  private async stop(vm: VirtualMachine, force: boolean): Promise<VirtualMachine> {
    if (vm.status === "stopped" || vm.status === "error") {
      if (vm.status === "error") {
        await this.killHelper(vm).catch(() => undefined);
        vm.status = "stopped";
        vm.progress = null;
        this.save(vm);
      }
      return vm;
    }
    if (vm.status === "building") {
      throw new VMValidationError("The image is still building", 409);
    }

    vm.status = "stopping";
    vm.progress = { phase: "stopping", message: force ? "Stopping the VM" : "Asking NixOS to shut down", startedAt: this.now() };
    this.save(vm);

    let error: string | null = null;
    try {
      const runtime = readRuntime(vm.paths.runtime);
      if (runtime && processAlive(runtime.pid)) {
        await stopHelperVM(runtime.controlPort, { force, timeoutMs: force ? 30_000 : 60_000 });
      }
    } catch (caught) {
      error = messageFor(caught);
    } finally {
      await this.killHelper(vm).catch(() => undefined);
      vm.status = "stopped";
      vm.progress = null;
      vm.lastError = error;
      vm.network.ip = null;
      vm.network.reachable = false;
      vm.metrics = null;
      vm.startedAt = undefined;
      this.save(vm);
    }
    return vm;
  }

  private async pause(vm: VirtualMachine): Promise<VirtualMachine> {
    if (vm.status !== "running") {
      throw new VMValidationError("Only a running VM can be paused", 409);
    }
    const runtime = readRuntime(vm.paths.runtime);
    if (!runtime) throw new VMValidationError("The VM helper is not running", 503);
    const status = await pauseHelperVM(runtime.controlPort);
    vm.status = status.state === "paused" ? "paused" : "running";
    this.save(vm);
    return vm;
  }

  private async resume(vm: VirtualMachine): Promise<VirtualMachine> {
    if (vm.status !== "paused") {
      throw new VMValidationError("Only a paused VM can be resumed", 409);
    }
    const runtime = readRuntime(vm.paths.runtime);
    if (!runtime) throw new VMValidationError("The VM helper is not running", 503);
    const status = await resumeHelperVM(runtime.controlPort);
    vm.status = status.state === "running" ? "running" : "paused";
    this.save(vm);
    return vm;
  }

  private async rebuild(vm: VirtualMachine, force: boolean): Promise<VirtualMachine> {
    if (this.builds.has(vm.id)) {
      throw new VMValidationError("The image is already building", 409);
    }
    if (vm.status === "running" || vm.status === "starting" || vm.status === "paused" || vm.status === "stopping") {
      throw new VMValidationError("Stop the virtual machine before rebuilding its image", 409);
    }
    if (existsSync(vm.paths.disk) && !force) {
      throw new VMValidationError(
        "Rebuilding replaces the guest disk and everything on it. Pass force=1 to confirm.",
        409,
      );
    }

    await this.killHelper(vm).catch(() => undefined);
    for (const path of [vm.paths.disk, vm.paths.serialLog, join(vm.paths.directory, "efi-vars.fd"), join(vm.paths.directory, "machine-id.bin"), join(vm.paths.directory, "result")]) {
      rmSync(path, { force: true });
    }
    vm.status = "building";
    vm.lastError = null;
    vm.network.ip = null;
    vm.network.reachable = false;
    vm.metrics = null;
    vm.progress = {
      phase: "queued",
      message: "Waiting to rebuild the NixOS image",
      startedAt: this.now(),
    };
    this.save(vm);
    this.startBuild(vm, true);
    return vm;
  }

  private async applyNow(vm: VirtualMachine): Promise<VirtualMachine> {
    if (vm.status !== "running") {
      throw new VMValidationError("Start the virtual machine before applying packages", 409);
    }
    if (this.applies.has(vm.id)) {
      return vm;
    }
    vm.pendingPackages = [...vm.packages];
    this.beginApply(vm);
    return vm;
  }

  // MARK: - Build

  private startBuild(vm: VirtualMachine, autostart: boolean): void {
    if (this.builds.has(vm.id)) return;
    this.builds.add(vm.id);
    void this.buildImage(vm, autostart)
      .catch((caught) => {
        const current = this.store.read(vm.id);
        if (!current) return;
        current.status = "error";
        current.lastError = messageFor(caught);
        current.progress = null;
        this.save(current);
      })
      .finally(() => {
        this.builds.delete(vm.id);
      });
  }

  private async buildImage(vm: VirtualMachine, autostart: boolean): Promise<void> {
    const capabilities = await this.capabilities();
    if (!capabilities.nixAvailable || !capabilities.nixPath) {
      throw new VMValidationError(
        "Nix is not installed. Install it from https://nixos.org/download and restart the hub.",
        409,
      );
    }
    if (!capabilities.linuxBuilder) {
      throw new VMValidationError(
        capabilities.linuxBuilderDetail ??
          "Nix has no aarch64-linux builder. Enable one (for example `nix run nixpkgs#darwin.linux-builder`) and restart the hub.",
        409,
      );
    }

    const current = this.store.read(vm.id);
    if (!current) return;
    current.status = "building";
    current.progress = {
      phase: "building",
      message: "Building the NixOS image. The first build can take a long time.",
      startedAt: this.now(),
    };
    current.lastError = null;
    this.save(current);

    resetLog(current.paths.buildLog);
    appendLog(
      current.paths.buildLog,
      `# ${new Date(this.now()).toISOString()}\n$ ${capabilities.nixPath} build --extra-experimental-features 'nix-command flakes' -L -o result ${IMAGE_ATTRIBUTE}\n\n`,
    );

    const exit = await this.runStreaming(
      capabilities.nixPath,
      [
        "build",
        "--extra-experimental-features",
        "nix-command flakes",
        "-L",
        "-o",
        "result",
        IMAGE_ATTRIBUTE,
      ],
      current.paths.directory,
      current.paths.buildLog,
      60 * 60_000,
      { ...this.env, NIX_NO_INTERACTIVE: "1" },
    );
    if (this.deleted.has(current.id)) return;
    if (exit !== 0) {
      throw new Error(lastLogLines(current.paths.buildLog, 8) || `Nix exited with code ${exit}`);
    }

    current.progress = {
      phase: "copying",
      message: "Copying the raw disk image out of the Nix store",
      startedAt: this.now(),
    };
    this.save(current);

    const output = this.resolveBuildOutput(current.paths.directory);
    rmSync(current.paths.disk, { force: true });
    let copy = await this.runner("cp", ["-c", output, current.paths.disk], 15 * 60_000);
    if (!copy.ok) {
      copy = await this.runner("cp", [output, current.paths.disk], 15 * 60_000);
    }
    if (!copy.ok) {
      throw new Error(`Could not copy the image: ${copy.stderr.trim() || copy.stdout.trim()}`);
    }
    chmodSync(current.paths.disk, 0o600);
    rmSync(join(current.paths.directory, "result"), { force: true });

    const latest = this.store.read(current.id) ?? current;
    latest.status = "stopped";
    latest.lastError = null;
    latest.progress = null;
    this.save(latest);
    appendLog(latest.paths.buildLog, `\n# Image ready at ${latest.paths.disk}\n`);

    if (autostart) {
      await this.start(latest).catch((caught) => {
        const failed = this.store.read(latest.id);
        if (!failed) return;
        failed.lastError = messageFor(caught);
        failed.progress = null;
        if (failed.status !== "running") failed.status = "error";
        this.save(failed);
      });
    }
  }

  private resolveBuildOutput(directory: string): string {
    const result = join(directory, "result");
    let target: string;
    try {
      target = realpathSync(result);
    } catch {
      throw new Error("Nix did not produce a result link. Check the build log.");
    }
    const stats = statSync(target);
    if (stats.isFile()) return target;

    const candidates = readdirSync(target)
      .filter((name) => name.endsWith(".img") || name.endsWith(".raw"))
      .map((name) => join(target, name));
    if (candidates.length === 0) {
      throw new Error("The Nix output does not contain a raw disk image");
    }
    candidates.sort((a, b) => statSync(b).size - statSync(a).size);
    return candidates[0]!;
  }

  // MARK: - Package application

  private beginApply(vm: VirtualMachine): void {
    if (this.applies.has(vm.id)) return;
    this.applies.add(vm.id);
    vm.progress = {
      phase: "applying",
      message: "Applying the NixOS configuration over SSH",
      startedAt: this.now(),
    };
    this.save(vm);
    void this.applyPackages(vm)
      .catch((caught) => {
        const current = this.store.read(vm.id);
        if (!current) return;
        current.lastError = messageFor(caught);
        current.progress = null;
        this.save(current);
      })
      .finally(() => {
        this.applies.delete(vm.id);
      });
  }

  private async applyPackages(vm: VirtualMachine): Promise<void> {
    // Re-read the definition so a package edit made while the previous apply
    // was finishing is not overwritten by a stale in-memory copy.
    const latest = this.store.read(vm.id) ?? vm;
    resetLog(latest.paths.applyLog);
    appendLog(latest.paths.applyLog, `# ${new Date(this.now()).toISOString()}\n`);

    if (!latest.network.reachable) {
      const reachable = await waitForGuestSSH(latest, this.runner, 60_000);
      if (!reachable) {
        throw new Error("The guest is not reachable over SSH yet. Try Apply again in a moment.");
      }
    }

    this.writeSources(latest);
    const remote = `/tmp/opencodebar-${latest.id}`;
    const files = [latest.paths.configuration, latest.paths.flake];
    const lock = join(latest.paths.directory, "flake.lock");
    if (existsSync(lock)) files.push(lock);

    const copied = await scpToGuest(latest, files, remote, this.runner, 60_000);
    if (!copied.ok) {
      throw new Error(copied.stderr.trim() || "Could not copy the NixOS configuration to the guest");
    }

    const hostname = guestHostname(latest);
    // `-n` fails fast instead of waiting for a password prompt on a
    // non-interactive SSH session. The generated guest configuration gives the
    // wheel group passwordless sudo.
    const command = [
      `sudo -n mkdir -p /etc/nixos ${shellQuote(`/etc/nixos/opencodebar-${latest.id}`)}`,
      `sudo -n cp ${shellQuote(`${remote}/configuration.nix`)} /etc/nixos/configuration.nix`,
      `sudo -n cp ${shellQuote(`${remote}/flake.nix`)} ${shellQuote(`/etc/nixos/opencodebar-${latest.id}/flake.nix`)}`,
      `if [ -f ${shellQuote(`${remote}/flake.lock`)} ]; then sudo -n cp ${shellQuote(`${remote}/flake.lock`)} ${shellQuote(`/etc/nixos/opencodebar-${latest.id}/flake.lock`)}; fi`,
      "sudo -n nixos-rebuild switch",
    ].join(" && ");
    appendLog(
      latest.paths.applyLog,
      `$ ssh ${latest.ssh.user}@${latest.network.ip} ${command}\n\n`,
    );

    const exit = await this.runStreaming(
      "ssh",
      [...sshArgsForStreaming(latest), `${latest.ssh.user}@${latest.network.ip}`, command],
      latest.paths.directory,
      latest.paths.applyLog,
      45 * 60_000,
    );
    if (this.deleted.has(latest.id)) return;
    if (exit !== 0) {
      throw new Error(
        lastLogLines(latest.paths.applyLog, 8) || `nixos-rebuild exited with code ${exit}`,
      );
    }

    const current = this.store.read(latest.id) ?? latest;
    // Only clear pending when the store still wants exactly what was applied;
    // a concurrent edit leaves a new pending list for the next apply.
    current.pendingPackages = sameStrings(current.packages, latest.packages)
      ? []
      : [...current.packages];
    current.lastError = null;
    current.progress = null;
    try {
      const metrics = await guestMetrics(current, this.runner);
      current.metrics = {
        collectedAt: this.now(),
        state: current.status,
        guest: metrics,
      };
      current.network.reachable = metrics.reachable;
    } catch {
      // Metrics are best-effort.
    }
    this.save(current);
    appendLog(
      latest.paths.applyLog,
      `\n# Configuration switched successfully on ${hostname}\n`,
    );
  }

  // MARK: - Reconciling and metrics

  private async reconcile(vm: VirtualMachine): Promise<void> {
    const now = this.now();
    const last = this.reconciledAt.get(vm.id) ?? 0;
    if (now - last < RECONCILE_TTL_MS) return;
    this.reconciledAt.set(vm.id, now);

    const before = statusSignature(vm);
    const previousStatus = vm.status;
    const runtime = readRuntime(vm.paths.runtime);
    const hasHelper = Boolean(runtime && processAlive(runtime.pid));
    const status = hasHelper && runtime ? await helperStatus(runtime.controlPort, 800) : null;

    if (status) {
      const next = statusFromHelper(status.state);
      if (next) vm.status = next;
      if (status.startedAt && !vm.startedAt) vm.startedAt = status.startedAt;
      if (status.error) vm.lastError = status.error;
      if (
        previousStatus === "running" &&
        vm.status === "stopped" &&
        !vm.lastError
      ) {
        vm.lastError = "The guest stopped unexpectedly. Check the serial log for details.";
      }
      if (vm.status === "running" && vm.progress?.phase === "starting") {
        vm.progress = {
          phase: "booting",
          message: "Waiting for NixOS to boot and publish its address",
          startedAt: now,
        };
      }
    } else if (runtime && !processAlive(runtime.pid)) {
      this.clearRuntime(vm);
      if (!this.builds.has(vm.id) && !this.applies.has(vm.id)) {
        if (vm.status !== "stopped") {
          const wasRunning = vm.status === "running" || vm.status === "starting" || vm.status === "paused";
          vm.status = "stopped";
          vm.startedAt = undefined;
          vm.network.ip = null;
          vm.network.reachable = false;
          vm.progress = null;
          if (wasRunning) {
            vm.lastError = "The VM helper exited unexpectedly. Check the serial log and start it again.";
          }
        }
      }
    } else if (!runtime && (vm.status === "running" || vm.status === "starting" || vm.status === "paused" || vm.status === "stopping")) {
      if (!this.builds.has(vm.id) && !this.applies.has(vm.id)) {
        vm.status = "stopped";
        vm.startedAt = undefined;
        vm.network.ip = null;
        vm.network.reachable = false;
        vm.progress = null;
        vm.lastError = "The VM helper is no longer running. Start the VM again.";
      }
    } else if (!runtime && vm.status === "building" && !this.builds.has(vm.id)) {
      // A hub restart loses the in-memory build job.
      vm.status = "error";
      vm.lastError = "The image build was interrupted when the hub restarted. Use rebuild to try again.";
      vm.progress = null;
    }

    if (vm.status === "running" && !vm.network.ip) {
      await this.discoverAddress(vm, 0);
    }

    if (statusSignature(vm) !== before) this.save(vm);
  }

  private async discoverAddress(vm: VirtualMachine, timeoutMs: number): Promise<string | null> {
    const deadline = this.now() + timeoutMs;
    do {
      const address = await findGuestAddress(vm, this.runner);
      if (address) {
        if (vm.network.ip !== address) {
          vm.network.ip = address;
          this.save(vm);
        }
        return address;
      }
      if (timeoutMs <= 0) break;
      await new Promise((resolve) => setTimeout(resolve, 1_000));
    } while (this.now() < deadline);
    return vm.network.ip;
  }

  private watchBoot(id: string): void {
    if (this.bootWaiters.has(id)) return;
    this.bootWaiters.add(id);
    void (async () => {
      const deadline = this.now() + BOOT_TIMEOUT_MS;
      while (this.now() < deadline) {
        const vm = this.store.read(id);
        if (!vm || vm.status !== "running") return;
        if (!vm.network.ip) {
          await this.discoverAddress(vm, 2_000);
        }
        if (vm.network.ip) {
          const reachable = await runGuest(vm, "true", this.runner, 5_000);
          if (reachable.ok) {
            const current = this.store.read(id);
            if (!current) return;
            current.network.reachable = true;
            if (current.progress?.phase === "booting") current.progress = null;
            this.metricsCache.delete(id);
            this.save(current);
            if (current.pendingPackages.length > 0) this.beginApply(current);
            return;
          }
        }
        await new Promise((resolve) => setTimeout(resolve, 2_000));
      }
      const current = this.store.read(id);
      if (current && current.progress?.phase === "booting") {
        current.progress = {
          phase: "booting",
          message: "NixOS is running, but SSH is not reachable yet. Check the serial console.",
          startedAt: current.progress.startedAt,
        };
        this.save(current);
      }
    })().finally(() => {
      this.bootWaiters.delete(id);
    });
  }

  private async refreshMetrics(vm: VirtualMachine): Promise<VMMetrics> {
    const existing = this.probes.get(vm.id);
    if (existing) return existing;
    const probe = collectMetrics(vm, this.runner)
      .then((value) => {
        this.metricsCache.set(vm.id, { at: this.now(), value });
        return value;
      })
      .finally(() => {
        this.probes.delete(vm.id);
      });
    this.probes.set(vm.id, probe);
    return probe;
  }

  // MARK: - Helpers

  private requireVM(id: string): VirtualMachine {
    const vm = this.store.read(id);
    if (!vm) throw new VMValidationError("Virtual machine not found", 404);
    return vm;
  }

  private save(vm: VirtualMachine): void {
    if (this.deleted.has(vm.id)) return;
    if (!this.store.exists(vm.id)) return;
    vm.updatedAt = this.now();
    this.store.write(vm);
  }

  private writeSources(vm: VirtualMachine): void {
    writeFileSync(vm.paths.configuration, renderConfiguration(vm, vm.packages), { mode: 0o600 });
    writeFileSync(vm.paths.flake, renderFlake(vm), { mode: 0o600 });
  }

  private writeHelperConfig(vm: VirtualMachine): void {
    const config = {
      id: vm.id,
      name: vm.name,
      cpuCount: vm.cpuCount,
      memoryBytes: vm.memoryMB * 1024 * 1024,
      diskPath: vm.paths.disk,
      efiVariableStore: join(vm.paths.directory, "efi-vars.fd"),
      machineIdentifier: join(vm.paths.directory, "machine-id.bin"),
      macAddress: vm.network.mac,
      serialLog: vm.paths.serialLog,
      runtimeFile: vm.paths.runtime,
      pidFile: join(vm.paths.directory, "helper.pid"),
    };
    writeFileSync(join(vm.paths.directory, "helper.json"), `${JSON.stringify(config, null, 2)}\n`, {
      mode: 0o600,
    });
  }

  private async createSSHKey(id: string, directory: string): Promise<string> {
    const keyPath = join(directory, "ssh", "id_ed25519");
    rmSync(keyPath, { force: true });
    rmSync(`${keyPath}.pub`, { force: true });
    const result = await this.runner(
      "ssh-keygen",
      ["-q", "-t", "ed25519", "-N", "", "-C", `opencodebar-${id}`, "-f", keyPath],
      15_000,
    );
    if (!result.ok) {
      throw new VMValidationError(
        `Could not generate an SSH key: ${result.stderr.trim() || "ssh-keygen failed"}`,
        500,
      );
    }
    chmodSync(keyPath, 0o600);
    return readFileSync(`${keyPath}.pub`, "utf8").trim();
  }

  private clearRuntime(vm: VirtualMachine): void {
    for (const path of [vm.paths.runtime, join(vm.paths.directory, "helper.pid")]) {
      rmSync(path, { force: true });
    }
  }

  private async killHelper(vm: VirtualMachine): Promise<void> {
    const runtime = readRuntime(vm.paths.runtime);
    if (runtime && processAlive(runtime.pid)) {
      try {
        process.kill(runtime.pid, "SIGTERM");
      } catch {
        // Already gone.
      }
      const deadline = Date.now() + 5_000;
      while (Date.now() < deadline && processAlive(runtime.pid)) {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
      if (processAlive(runtime.pid)) {
        try {
          process.kill(runtime.pid, "SIGKILL");
        } catch {
          // Already gone.
        }
      }
    }
    this.clearRuntime(vm);
  }

  private async runStreaming(
    command: string,
    args: string[],
    cwd: string,
    logPath: string,
    timeoutMs: number,
    env: NodeJS.ProcessEnv = this.env,
  ): Promise<number> {
    const proc = Bun.spawn([command, ...args], {
      cwd,
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
      env: { ...env },
    });
    const writer = createLogWriter(logPath);
    const pumps = [pump(proc.stdout, writer), pump(proc.stderr, writer)];
    let timer: ReturnType<typeof setTimeout> | null = null;
    if (timeoutMs > 0) {
      timer = setTimeout(() => {
        try {
          proc.kill();
        } catch {
          // Already exited.
        }
      }, timeoutMs);
    }
    try {
      return await proc.exited;
    } finally {
      if (timer) clearTimeout(timer);
      await Promise.allSettled(pumps);
    }
  }
}

function logPath(vm: VirtualMachine, type: VMLogType): string {
  if (type === "serial") return vm.paths.serialLog;
  if (type === "apply") return vm.paths.applyLog;
  return vm.paths.buildLog;
}

function statusSignature(vm: VirtualMachine): string {
  return JSON.stringify({
    status: vm.status,
    ip: vm.network.ip,
    reachable: vm.network.reachable,
    startedAt: vm.startedAt,
    error: vm.lastError,
    progress: vm.progress?.phase ?? null,
  });
}

function statusFromHelper(state: HelperStatus["state"]): VMStatus | null {
  switch (state) {
    case "running":
      return "running";
    case "paused":
      return "paused";
    case "starting":
      return "starting";
    case "stopping":
      return "stopping";
    case "stopped":
      return "stopped";
    case "error":
      return "error";
    default:
      return null;
  }
}

function lastLogLines(path: string, count: number): string {
  const tail = readLogTail(path, count, 64 * 1024);
  return tail.lines.filter((line) => line.trim()).slice(-count).join("\n");
}

async function readTextStream(stream: ReadableStream<Uint8Array> | undefined): Promise<string> {
  if (!stream) return "";
  return new Response(stream).text();
}

async function pump(
  stream: ReadableStream<Uint8Array> | undefined,
  write: (chunk: string) => void,
): Promise<void> {
  if (!stream) return;
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (value && value.byteLength > 0) write(decoder.decode(value, { stream: true }));
    }
    const rest = decoder.decode();
    if (rest) write(rest);
  } catch {
    // The process ended while a pipe was being read.
  } finally {
    reader.releaseLock();
  }
}

function sameStrings(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const left = [...a].sort();
  const right = [...b].sort();
  return left.every((value, index) => value === right[index]);
}

function sshArgsForStreaming(vm: VirtualMachine): string[] {
  return [
    "-i",
    vm.ssh.keyPath,
    "-p",
    "22",
    "-o",
    "BatchMode=yes",
    "-o",
    "ConnectTimeout=5",
    "-o",
    "StrictHostKeyChecking=accept-new",
    "-o",
    `UserKnownHostsFile=${join(vm.paths.directory, "ssh", "known_hosts")}`,
    "-o",
    "LogLevel=ERROR",
  ];
}

function messageFor(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}
