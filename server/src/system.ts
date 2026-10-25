import { execFile } from "node:child_process";
import { accessSync, constants, readFileSync, readdirSync, statSync } from "node:fs";
import {
  arch,
  cpus,
  freemem,
  homedir,
  hostname,
  loadavg,
  networkInterfaces,
  platform,
  release,
  totalmem,
  type,
  uptime,
  userInfo,
} from "node:os";
import { basename, delimiter, join } from "node:path";
import { HUB_VERSION } from "./config.ts";
import type {
  MediaControlResult,
  SystemApp,
  SystemAudio,
  SystemBattery,
  SystemBrewPackage,
  SystemCPU,
  SystemDisk,
  SystemDisplayGroup,
  SystemDocker,
  SystemHomebrew,
  SystemHost,
  SystemInfo,
  SystemMedia,
  SystemMemory,
  SystemNetwork,
  SystemPort,
  SystemProcess,
  SystemRuntime,
  SystemSecurity,
  SystemThermal,
} from "./types.ts";

export interface CommandResult {
  ok: boolean;
  stdout: string;
  stderr: string;
}

export type CommandRunner = (
  command: string,
  args: string[],
  timeoutMs?: number,
  env?: NodeJS.ProcessEnv,
) => Promise<CommandResult>;

export interface SystemInfoOptions {
  runner?: CommandRunner;
  /** How long the expensive, rarely changing collectors stay cached. */
  staticTTLMs?: number;
  /** How long a complete snapshot is reused between clients. */
  cacheTTLMs?: number;
  hub?: () => {
    startedAt: number;
    port?: number;
    dbPath?: string;
  };
}

interface StaticInfo {
  host: Partial<SystemHost>;
  cpu: Partial<SystemCPU>;
  memory: Partial<SystemMemory>;
  apps: SystemApp[];
  homebrew: SystemHomebrew | null;
  runtimes: SystemRuntime[];
  displays: SystemDisplayGroup[];
  security: SystemSecurity | null;
}

const DEFAULT_STATIC_TTL_MS = 5 * 60_000;
const DEFAULT_CACHE_TTL_MS = 2_000;
const COMMAND_TIMEOUT_MS = 5_000;
const LONG_COMMAND_TIMEOUT_MS = 20_000;

export class MediaControlError extends Error {
  readonly status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.name = "MediaControlError";
    this.status = status;
  }
}

const MEDIA_COMMANDS: Record<string, number> = {
  toggle: 2,
  play: 0,
  pause: 1,
  stop: 3,
  next: 4,
  previous: 5,
  back15: 12,
  forward15: 13,
};

const APP_DIRECTORIES = [
  "/Applications",
  "/Applications/Utilities",
  "/System/Applications",
  "/System/Applications/Utilities",
  "/System/Library/CoreServices/Applications",
];

/**
 * JXA reads the same MediaRemote item that macOS shows in Control Center. It
 * returns the owning app and metadata for any player, including browsers.
 */
const NOW_PLAYING_SCRIPT = String.raw`function run() {
  try {
    const bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    bundle.load;
    const Request = $.NSClassFromString('MRNowPlayingRequest');
    if (!Request) return JSON.stringify({ error: 'MediaRemote unavailable' });
    const path = Request.localNowPlayingPlayerPath;
    const info = Request.localNowPlayingItem.nowPlayingInfo;
    const read = (key) => {
      if (!info) return null;
      const value = info.valueForKey(key);
      if (!value) return null;
      const converted = value.js;
      return converted === undefined ? null : converted;
    };
    const appName = path && path.client && path.client.displayName ? path.client.displayName.js : null;
    const bundleID = path && path.client && path.client.bundleIdentifier ? path.client.bundleIdentifier.js : null;
    const title = read('kMRMediaRemoteNowPlayingInfoTitle');
    if (!appName && !title) return JSON.stringify({ media: [] });
    const rate = read('kMRMediaRemoteNowPlayingInfoPlaybackRate');
    const supported = [];
    const commands = Request.localSupportedCommands;
    if (commands) {
      for (let index = 0; index < commands.count; index += 1) {
        try {
          const info = commands.objectAtIndex(index);
          const command = info.command;
          if (command) supported.push(command.js);
        } catch (_) {}
      }
    }
    return JSON.stringify({ media: [{
      app: appName || 'Unknown app',
      bundleID: bundleID || null,
      title: title || null,
      artist: read('kMRMediaRemoteNowPlayingInfoArtist') || null,
      album: read('kMRMediaRemoteNowPlayingInfoAlbum') || null,
      elapsedSeconds: read('kMRMediaRemoteNowPlayingInfoElapsedTime'),
      durationSeconds: read('kMRMediaRemoteNowPlayingInfoDuration'),
      playbackRate: rate,
      state: rate === 0 ? 'paused' : 'playing',
      source: 'mediaremote',
      supportedCommands: supported
    }] });
  } catch (error) {
    return JSON.stringify({ error: String(error) });
  }
}`;

/**
 * Sends one MediaRemote command to the current player. The integer is passed as
 * the first osascript argument by the hub.
 */
const MEDIA_CONTROL_SCRIPT = String.raw`function run(argv) {
  try {
    const command = parseInt(argv[0] || '-1', 10);
    if (!Number.isFinite(command) || command < 0) return JSON.stringify({ ok: false, error: 'Invalid command' });
    const bundle = $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/');
    bundle.load;
    const Request = $.NSClassFromString('MRNowPlayingRequest');
    if (!Request) return JSON.stringify({ ok: false, error: 'MediaRemote unavailable' });
    const path = Request.localNowPlayingPlayerPath;
    if (!path) return JSON.stringify({ ok: false, error: 'Nothing is playing' });
    const request = Request.alloc.initWithPlayerPath(path);
    request.sendCommandOptionsQueueCompletion(command, $.NSDictionary.dictionary, $.NSOperationQueue.mainQueue, null);
    return JSON.stringify({ ok: true });
  } catch (error) {
    return JSON.stringify({ ok: false, error: String(error) });
  }
}`;

const APPLESCRIPT_MEDIA_SCRIPT = String.raw`set output to ""
if application "Music" is running then
  tell application "Music"
    if player state is not stopped then
      set output to output & "Music" & tab & (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text) & linefeed
    end if
  end tell
end if
if application "Spotify" is running then
  tell application "Spotify"
    if player state is not stopped then
      set output to output & "Spotify" & tab & (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (player position as text) & tab & (duration of current track as text) & linefeed
    end if
  end tell
end if
return output`;

const TOOL_COMMANDS: Array<{
  name: string;
  command: string;
  args: string[];
  kind: SystemRuntime["kind"];
}> = [
  { name: "Node.js", command: "node", args: ["--version"], kind: "runtime" },
  { name: "Bun", command: "bun", args: ["--version"], kind: "runtime" },
  { name: "Deno", command: "deno", args: ["--version"], kind: "runtime" },
  { name: "Python", command: "python3", args: ["--version"], kind: "runtime" },
  { name: "pip", command: "pip3", args: ["--version"], kind: "tool" },
  { name: "Go", command: "go", args: ["version"], kind: "runtime" },
  { name: "Rust", command: "rustc", args: ["--version"], kind: "runtime" },
  { name: "Cargo", command: "cargo", args: ["--version"], kind: "tool" },
  { name: "Java", command: "java", args: ["-version"], kind: "runtime" },
  { name: "Swift", command: "swift", args: ["--version"], kind: "runtime" },
  { name: "Ruby", command: "ruby", args: ["--version"], kind: "runtime" },
  { name: "PHP", command: "php", args: ["--version"], kind: "runtime" },
  { name: "Git", command: "git", args: ["--version"], kind: "tool" },
  { name: "npm", command: "npm", args: ["--version"], kind: "tool" },
  { name: "pnpm", command: "pnpm", args: ["--version"], kind: "tool" },
  { name: "Yarn", command: "yarn", args: ["--version"], kind: "tool" },
  { name: "Docker", command: "docker", args: ["--version"], kind: "tool" },
  { name: "kubectl", command: "kubectl", args: ["version", "--client"], kind: "tool" },
  { name: "GitHub CLI", command: "gh", args: ["--version"], kind: "tool" },
  { name: "Clang", command: "clang", args: ["--version"], kind: "tool" },
  { name: "CMake", command: "cmake", args: ["--version"], kind: "tool" },
  { name: "Make", command: "make", args: ["--version"], kind: "tool" },
  { name: "SQLite", command: "sqlite3", args: ["--version"], kind: "tool" },
  { name: "FFmpeg", command: "ffmpeg", args: ["-version"], kind: "tool" },
  { name: "Terraform", command: "terraform", args: ["version"], kind: "tool" },
  { name: "AWS CLI", command: "aws", args: ["--version"], kind: "tool" },
  { name: "Google Cloud", command: "gcloud", args: ["--version"], kind: "tool" },
];

const defaultRunner: CommandRunner = (command, args, timeoutMs = COMMAND_TIMEOUT_MS, env) =>
  new Promise((resolve) => {
    execFile(
      command,
      args,
      {
        timeout: timeoutMs,
        maxBuffer: 16 * 1024 * 1024,
        encoding: "utf8",
        windowsHide: true,
        env: env ?? process.env,
      },
      (error, stdout, stderr) => {
        resolve({
          ok: !error,
          stdout: typeof stdout === "string" ? stdout : "",
          stderr: typeof stderr === "string" ? stderr : "",
        });
      },
    );
  });

/**
 * Collects a full snapshot of the machine running the hub. Dynamic facts (load,
 * memory, disks, processes) are refreshed on every request; expensive static
 * facts (installed apps, Homebrew, toolchain versions, displays) are cached.
 */
export class SystemInfoService {
  private readonly runner: CommandRunner;
  private readonly staticTTLMs: number;
  private readonly cacheTTLMs: number;
  private readonly hub: SystemInfoOptions["hub"];

  private staticCache: { at: number; value: StaticInfo } | null = null;
  private staticInFlight: Promise<StaticInfo> | null = null;
  private snapshotCache: { at: number; value: SystemInfo } | null = null;
  private snapshotInFlight: Promise<SystemInfo> | null = null;
  private previousCPU: Array<{ total: number; idle: number }> | null = null;
  private lastDocker: { at: number; value: SystemDocker | null } | null = null;

  constructor(options: SystemInfoOptions = {}) {
    this.runner = options.runner ?? defaultRunner;
    this.staticTTLMs = options.staticTTLMs ?? DEFAULT_STATIC_TTL_MS;
    this.cacheTTLMs = options.cacheTTLMs ?? DEFAULT_CACHE_TTL_MS;
    this.hub = options.hub;
  }

  async snapshot(force = false): Promise<SystemInfo> {
    const now = Date.now();
    if (!force && this.snapshotCache && now - this.snapshotCache.at < this.cacheTTLMs) {
      return this.snapshotCache.value;
    }
    if (this.snapshotInFlight) return this.snapshotInFlight;

    this.snapshotInFlight = this.build(force)
      .then((value) => {
        this.snapshotCache = { at: Date.now(), value };
        return value;
      })
      .finally(() => {
        this.snapshotInFlight = null;
      });
    return this.snapshotInFlight;
  }

  private async staticInfo(force: boolean): Promise<StaticInfo> {
    const now = Date.now();
    if (!force && this.staticCache && now - this.staticCache.at < this.staticTTLMs) {
      return this.staticCache.value;
    }
    if (this.staticInFlight) return this.staticInFlight;

    this.staticInFlight = this.collectStatic()
      .then((value) => {
        this.staticCache = { at: Date.now(), value };
        return value;
      })
      .finally(() => {
        this.staticInFlight = null;
      });
    return this.staticInFlight;
  }

  private async build(force: boolean): Promise<SystemInfo> {
    // The five-second poll reuses the expensive inventory; an explicit refresh
    // re-scans it so newly installed apps and packages show up immediately.
    const staticInfo = await this.staticInfo(force);
    const notes: string[] = [];

    const [disks, processes, battery, thermal, listeningPorts, docker, network, media, audio] =
      await Promise.all([
        this.collectDisks(),
        this.collectProcesses(),
        this.collectBattery(),
        this.collectThermal(),
        this.collectListeningPorts(),
        this.collectDocker(),
        this.collectNetwork(),
        this.collectMedia(),
        this.collectAudio(),
      ]);

    const cpuUsage = this.sampleCPUUsage();
    const memory = this.collectMemory(staticInfo.memory);
    const now = Date.now();
    const bootedAt = now - uptime() * 1_000;
    const hubMeta = this.hub?.() ?? { startedAt: now - process.uptime() * 1_000 };

    if (!staticInfo.homebrew?.available) {
      notes.push("Homebrew was not found on PATH.");
    }
    if (staticInfo.apps.length === 0) {
      notes.push("Installed applications could not be enumerated on this system.");
    }

    return {
      generatedAt: now,
      platform: platform(),
      platformName: platformName(),
      host: {
        name: staticInfo.host.name ?? hostname(),
        hostname: hostname(),
        platform: platform(),
        platformName: platformName(),
        kernel: release(),
        arch: arch(),
        ...staticInfo.host,
        uptime: Math.round(uptime()),
        bootedAt,
      },
      hub: {
        version: HUB_VERSION,
        pid: process.pid,
        runtime: "Bun",
        runtimeVersion: process.versions.bun ?? process.version,
        startedAt: hubMeta.startedAt,
        uptime: Math.max(0, Math.round((now - hubMeta.startedAt) / 1_000)),
        port: hubMeta.port,
        dbPath: hubMeta.dbPath,
        dbSizeBytes: fileSize(hubMeta.dbPath),
        cwd: safeCwd(),
        execPath: process.execPath,
        memoryBytes: process.memoryUsage().heapTotal,
        rssBytes: process.memoryUsage().rss,
        heapUsedBytes: process.memoryUsage().heapUsed,
      },
      cpu: {
        architecture: arch(),
        logicalCores: cpus().length,
        speedMHz: cpus()[0]?.speed,
        model: staticInfo.cpu.model,
        vendor: staticInfo.cpu.vendor,
        physicalCores: staticInfo.cpu.physicalCores,
        usagePercent: cpuUsage.usagePercent,
        perCoreUsage: cpuUsage.perCoreUsage,
        loadAverage: loadavg().map((value) => round(value, 2)),
        temperatureC: thermal?.temperatureC,
      },
      memory,
      disks,
      network,
      processes,
      battery,
      thermal,
      security: staticInfo.security,
      apps: staticInfo.apps,
      homebrew: staticInfo.homebrew,
      runtimes: staticInfo.runtimes,
      displays: staticInfo.displays,
      listeningPorts,
      docker,
      media,
      audio,
      notes,
    };
  }

  // MARK: - Static collectors

  private async collectStatic(): Promise<StaticInfo> {
    const info: StaticInfo = {
      host: {},
      cpu: {},
      memory: {},
      apps: [],
      homebrew: null,
      runtimes: [],
      displays: [],
      security: null,
    };

    const tasks: Array<Promise<void>> = [
      this.collectOS(info),
      this.collectHardware(info),
      this.collectApps().then((apps) => {
        info.apps = apps;
      }),
      this.collectHomebrew().then((brew) => {
        info.homebrew = brew;
      }),
      this.collectRuntimes().then((runtimes) => {
        info.runtimes = runtimes;
      }),
      this.collectDisplays().then((displays) => {
        info.displays = displays;
      }),
      this.collectSecurity().then((security) => {
        info.security = security;
      }),
    ];

    await Promise.allSettled(tasks);
    return info;
  }

  private async collectOS(info: StaticInfo): Promise<void> {
    const os = platform();
    info.host.platform = os;
    info.host.platformName = platformName();
    info.host.kernel = release();
    info.host.arch = arch();
    info.host.username = safeUsername();
    info.host.home = homedir();
    info.host.shell = process.env.SHELL;
    info.host.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    info.host.locale = process.env.LANG ?? Intl.DateTimeFormat().resolvedOptions().locale;

    if (os === "darwin") {
      const [swVers, computerName, virt] = await Promise.all([
        this.run("sw_vers", [], COMMAND_TIMEOUT_MS),
        this.run("scutil", ["--get", "ComputerName"], COMMAND_TIMEOUT_MS),
        this.run("sysctl", ["-n", "kern.hv_vmm_present"], COMMAND_TIMEOUT_MS),
      ]);
      const values = parseKeyValueLines(text(swVers));
      info.host.osName = values.ProductName;
      info.host.osVersion = values.ProductVersion;
      info.host.osBuild = values.BuildVersion;
      info.host.name = firstLine(text(computerName)) || hostname();
      const hv = firstLine(text(virt));
      if (hv === "1") info.host.isVirtualMachine = true;
      if (hv === "1") info.host.virtualization = "virtual machine";
      return;
    }

    if (os === "linux") {
      const releaseInfo = parseOSRelease(readFileSafe("/etc/os-release"));
      info.host.osName = releaseInfo.NAME ?? "Linux";
      info.host.osVersion = releaseInfo.VERSION ?? releaseInfo.VERSION_ID;
      info.host.osBuild = releaseInfo.BUILD_ID;
      info.host.name = hostname();
      const [virt, kernel] = await Promise.all([
        this.run("systemd-detect-virt", [], COMMAND_TIMEOUT_MS),
        this.run("uname", ["-r"], COMMAND_TIMEOUT_MS),
      ]);
      const virtName = firstLine(text(virt));
      if (virtName && virtName !== "none") {
        info.host.isVirtualMachine = true;
        info.host.virtualization = virtName;
      }
      const kernelLine = firstLine(text(kernel));
      if (kernelLine) info.host.kernel = kernelLine;
      return;
    }

    if (os === "win32") {
      const result = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const value = parseJSONRecord(firstLine(text(result)));
      info.host.osName = stringValue(value?.Caption) ?? "Windows";
      info.host.osVersion = stringValue(value?.Version);
      info.host.osBuild = stringValue(value?.BuildNumber);
      info.host.name = hostname();
      info.host.shell = process.env.COMSPEC;
    }
  }

  private async collectHardware(info: StaticInfo): Promise<void> {
    const os = platform();
    const logical = cpus().length;
    info.cpu.logicalCores = logical;
    info.cpu.architecture = arch();
    info.cpu.speedMHz = cpus()[0]?.speed;
    info.cpu.model = cpuModel();

    if (os === "darwin") {
      const [hw, physical, brand, model] = await Promise.all([
        this.run(
          "system_profiler",
          ["SPHardwareDataType", "-json", "-detailLevel", "mini"],
          LONG_COMMAND_TIMEOUT_MS,
        ),
        this.run("sysctl", ["-n", "hw.physicalcpu"], COMMAND_TIMEOUT_MS),
        this.run("sysctl", ["-n", "machdep.cpu.brand_string"], COMMAND_TIMEOUT_MS),
        this.run("sysctl", ["-n", "hw.model"], COMMAND_TIMEOUT_MS),
      ]);
      const hardware = firstObject(parseJSON(text(hw))?.SPHardwareDataType);
      info.host.model = stringValue(hardware?.machine_name);
      info.host.chip = stringValue(hardware?.chip_type);
      info.host.machine = stringValue(hardware?.machine_model) ?? firstLine(text(model));
      info.host.osName = info.host.osName ?? "macOS";
      info.cpu.model = info.host.chip ?? firstLine(text(brand)) ?? info.cpu.model;
      info.cpu.vendor = "Apple";
      const cores = Number.parseInt(firstLine(text(physical)) ?? "", 10);
      if (Number.isFinite(cores)) info.cpu.physicalCores = cores;

      const swap = parseSwapUsage(text(await this.run("sysctl", ["-n", "vm.swapusage"], COMMAND_TIMEOUT_MS)));
      info.memory.swapTotalBytes = swap.total;
      info.memory.swapUsedBytes = swap.used;
      info.memory.swapFreeBytes = swap.free;
      Object.assign(info.memory, parseVMStat(text(await this.run("vm_stat", [], COMMAND_TIMEOUT_MS))));
      return;
    }

    if (os === "linux") {
      const cpuinfo = readFileSafe("/proc/cpuinfo");
      info.cpu.model = info.cpu.model ?? parseLinuxCPUModel(cpuinfo);
      info.cpu.vendor = parseLinuxCPUVendor(cpuinfo);
      info.cpu.physicalCores = parseLinuxPhysicalCores(cpuinfo);
      Object.assign(info.memory, parseMemInfo(readFileSafe("/proc/meminfo")));
      const model = readFileSafe("/proc/device-tree/model").replace(/\0/g, "").trim();
      if (model) info.host.model = model;
      return;
    }

    if (os === "win32") {
      const result = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-CimInstance Win32_Processor | Select-Object -First 1 Name,Manufacturer,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const cpu = parseJSONRecord(firstLine(text(result)));
      info.cpu.model = stringValue(cpu?.Name) ?? info.cpu.model;
      info.cpu.vendor = stringValue(cpu?.Manufacturer);
      info.cpu.physicalCores = numberValue(cpu?.NumberOfCores);
      const cores = numberValue(cpu?.NumberOfLogicalProcessors);
      if (cores) info.cpu.logicalCores = cores;
      info.cpu.speedMHz = numberValue(cpu?.MaxClockSpeed);
      info.host.osName = info.host.osName ?? "Windows";

      const computer = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const system = parseJSONRecord(firstLine(text(computer)));
      info.host.model = stringValue(system?.Model);
      info.host.machine = stringValue(system?.Manufacturer);
    }
  }

  private async collectApps(): Promise<SystemApp[]> {
    const os = platform();
    try {
      if (os === "darwin") return await this.collectMacApps();
      if (os === "linux") return this.collectLinuxApps();
      if (os === "win32") return await this.collectWindowsApps();
    } catch {
      // Fall through to an empty list; the endpoint still returns everything else.
    }
    return [];
  }

  private async collectMacApps(): Promise<SystemApp[]> {
    const result = await this.run(
      "system_profiler",
      ["SPApplicationsDataType", "-json", "-detailLevel", "mini"],
      LONG_COMMAND_TIMEOUT_MS,
    );
    const entries = parseJSON(text(result))?.SPApplicationsDataType;
    if (!Array.isArray(entries)) return this.scanAppDirectories();

    const apps: SystemApp[] = [];
    for (const raw of entries) {
      const entry = asRecord(raw);
      if (!entry) continue;
      const path = stringValue(entry.path);
      const name = stringValue(entry._name) ?? (path ? basename(path, ".app") : undefined);
      if (!name || !path) continue;
      apps.push({
        name,
        path,
        version: stringValue(entry.version),
        bundleID: stringValue(entry.bundleid),
        source: stringValue(entry.obtained_from),
        architecture: stringValue(entry.arch_kind),
        lastModified: stringValue(entry.lastModified),
      });
    }
    apps.sort((a, b) => a.name.localeCompare(b.name));
    return apps;
  }

  private scanAppDirectories(): SystemApp[] {
    const apps: SystemApp[] = [];
    const seen = new Set<string>();
    for (const directory of APP_DIRECTORIES) {
      const paths = listDirectory(directory);
      for (const entry of paths) {
        if (!entry.endsWith(".app")) continue;
        const path = join(directory, entry);
        if (seen.has(path)) continue;
        seen.add(path);
        apps.push({ name: basename(entry, ".app"), path });
      }
    }
    apps.sort((a, b) => a.name.localeCompare(b.name));
    return apps;
  }

  private collectLinuxApps(): SystemApp[] {
    const directories = [
      "/usr/share/applications",
      "/usr/local/share/applications",
      join(homedir(), ".local", "share", "applications"),
      "/var/lib/flatpak/exports/share/applications",
      join(homedir(), ".local", "share", "flatpak", "exports", "share", "applications"),
      "/var/lib/snapd/desktop/applications",
    ];
    const apps: SystemApp[] = [];
    const seen = new Set<string>();

    for (const directory of directories) {
      for (const entry of listDirectory(directory)) {
        if (!entry.endsWith(".desktop")) continue;
        const path = join(directory, entry);
        const values = parseDesktopEntry(readFileSafe(path));
        const name = values.Name;
        if (!name || seen.has(name)) continue;
        seen.add(name);
        apps.push({
          name,
          path,
          version: values.Version,
          bundleID: values.StartupWMClass,
          source: values.Exec ? "desktop entry" : undefined,
        });
      }
    }
    apps.sort((a, b) => a.name.localeCompare(b.name));
    return apps;
  }

  private async collectWindowsApps(): Promise<SystemApp[]> {
    const result = await this.run(
      "powershell",
      [
        "-NoProfile",
        "-NonInteractive",
        "-Command",
        "$paths=@('HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\Software\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*'); Get-ItemProperty $paths -ErrorAction SilentlyContinue | Where-Object DisplayName | Select-Object DisplayName,DisplayVersion,InstallLocation,Publisher | ConvertTo-Json -Compress",
      ],
      LONG_COMMAND_TIMEOUT_MS,
    );
    const raw = parseJSONValue(text(result));
    const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
    const apps: SystemApp[] = [];
    for (const rawEntry of entries) {
      const entry = asRecord(rawEntry);
      const name = stringValue(entry?.DisplayName);
      if (!name) continue;
      apps.push({
        name,
        path: stringValue(entry?.InstallLocation) ?? "",
        version: stringValue(entry?.DisplayVersion),
        source: stringValue(entry?.Publisher),
      });
    }
    apps.sort((a, b) => a.name.localeCompare(b.name));
    return apps;
  }

  private async collectHomebrew(): Promise<SystemHomebrew> {
    const brew = findExecutable("brew") ?? findExecutable("brew", ["/opt/homebrew/bin", "/usr/local/bin", "/home/linuxbrew/.linuxbrew/bin"]);
    if (!brew) {
      return { available: false, formulaCount: 0, caskCount: 0, outdatedCount: 0, packages: [] };
    }

    const env = { ...process.env, HOMEBREW_NO_AUTO_UPDATE: "1", HOMEBREW_NO_INSTALL_CLEANUP: "1" };
    const [versionResult, prefixResult, formulaResult, caskResult, outdatedResult] = await Promise.all([
      this.run(brew, ["--version"], COMMAND_TIMEOUT_MS, env),
      this.run(brew, ["--prefix"], COMMAND_TIMEOUT_MS, env),
      this.run(brew, ["list", "--versions"], LONG_COMMAND_TIMEOUT_MS, env),
      this.run(brew, ["list", "--cask", "--versions"], LONG_COMMAND_TIMEOUT_MS, env),
      this.run(brew, ["outdated", "--quiet"], LONG_COMMAND_TIMEOUT_MS, env),
    ]);

    const outdated = new Set(lines(text(outdatedResult)));
    const formulae = parseBrewVersions(text(formulaResult), "formula", outdated);
    const casks = parseBrewVersions(text(caskResult), "cask", outdated);
    const packages = [...formulae, ...casks].sort((a, b) => {
      if (a.kind !== b.kind) return a.kind === "formula" ? -1 : 1;
      return a.name.localeCompare(b.name);
    });

    return {
      available: true,
      version: firstLine(text(versionResult))?.replace(/^Homebrew\s+/, "Homebrew "),
      prefix: firstLine(text(prefixResult)),
      formulaCount: formulae.length,
      caskCount: casks.length,
      outdatedCount: outdated.size,
      packages,
    };
  }

  private async collectRuntimes(): Promise<SystemRuntime[]> {
    const results = await Promise.all(
      TOOL_COMMANDS.map(async (tool): Promise<SystemRuntime | null> => {
        const path = findExecutable(tool.command);
        if (!path) return null;
        const result = await this.run(path, tool.args, 3_000);
        const output = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
        if (!result.ok && !output) return null;
        return {
          name: tool.name,
          version: cleanVersion(tool.name, output),
          path,
          kind: tool.kind,
        };
      }),
    );
    return results.filter((entry): entry is SystemRuntime => entry !== null);
  }

  private async collectDisplays(): Promise<SystemDisplayGroup[]> {
    const os = platform();
    if (os === "darwin") {
      const result = await this.run(
        "system_profiler",
        ["SPDisplaysDataType", "-json", "-detailLevel", "mini"],
        LONG_COMMAND_TIMEOUT_MS,
      );
      const entries = parseJSON(text(result))?.SPDisplaysDataType;
      if (!Array.isArray(entries)) return [];
      const groups: SystemDisplayGroup[] = [];
      for (const raw of entries) {
        const entry = asRecord(raw);
        if (!entry) continue;
        const displaysRaw = entry.spdisplays_ndrvs;
        const displays = Array.isArray(displaysRaw)
          ? displaysRaw.flatMap((displayRaw) => {
              const display = asRecord(displayRaw);
              if (!display) return [];
              const name = stringValue(display._name) ?? "Display";
              return [{
                name,
                resolution: stringValue(display["_spdisplays_resolution"]) ?? stringValue(display.spdisplays_resolution),
                pixels: stringValue(display["_spdisplays_pixels"]) ?? stringValue(display.spdisplays_pixels),
                type: stringValue(display.spdisplays_connection_type)?.replace(/^spdisplays_/, ""),
                main: stringValue(display.spdisplays_main) === "spdisplays_yes",
                online: stringValue(display.spdisplays_online) !== "spdisplays_no",
                mirror: stringValue(display.spdisplays_mirror) === "spdisplays_on",
              }];
            })
          : [];
        groups.push({
          name: stringValue(entry._name) ?? "GPU",
          vendor: stringValue(entry.spdisplays_vendor)?.replace(/^sppci_vendor_/, ""),
          model: stringValue(entry.sppci_model),
          cores: numberValue(entry.sppci_cores),
          displays,
        });
      }
      return groups;
    }

    if (os === "linux") {
      const result = await this.run("xrandr", ["--query"], COMMAND_TIMEOUT_MS);
      if (!result.ok) return [];
      const displays = text(result)
        .split("\n")
        .flatMap((line) => {
          const match = line.match(/^(\S+)\s+connected(?:\s+primary)?\s+(\d+)x(\d+)/);
          if (!match) return [];
          return [{
            name: match[1] ?? "Display",
            resolution: `${match[2]} x ${match[3]}`,
            main: line.includes(" connected primary "),
            online: true,
          }];
        });
      return displays.length > 0 ? [{ name: "Displays", displays }] : [];
    }

    if (os === "win32") {
      const result = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,AdapterRAM | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const raw = parseJSONValue(text(result));
      const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
      return entries.flatMap((rawEntry) => {
        const entry = asRecord(rawEntry);
        const name = stringValue(entry?.Name);
        if (!name) return [];
        const width = numberValue(entry?.CurrentHorizontalResolution);
        const height = numberValue(entry?.CurrentVerticalResolution);
        return [{
          name,
          model: name,
          displays: [{
            name,
            resolution: width && height ? `${width} x ${height}` : undefined,
            online: true,
          }],
        }];
      });
    }

    return [];
  }

  private async collectSecurity(): Promise<SystemSecurity | null> {
    const os = platform();
    if (os === "darwin") {
      const [sip, vault, firewall, gatekeeper] = await Promise.all([
        this.run("csrutil", ["status"], COMMAND_TIMEOUT_MS),
        this.run("fdesetup", ["status"], COMMAND_TIMEOUT_MS),
        this.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"], COMMAND_TIMEOUT_MS),
        this.run("spctl", ["--status"], COMMAND_TIMEOUT_MS),
      ]);
      return {
        systemIntegrityProtection: parseOnOff(text(sip)),
        fileVault: parseOnOff(text(vault)),
        firewall: parseOnOff(text(firewall)),
        gatekeeper: parseOnOff(text(gatekeeper)),
      };
    }

    if (os === "linux") {
      const [ufw, selinux, apparmor] = await Promise.all([
        this.run("ufw", ["status"], COMMAND_TIMEOUT_MS),
        this.run("getenforce", [], COMMAND_TIMEOUT_MS),
        this.run("aa-status", ["--enabled"], COMMAND_TIMEOUT_MS),
      ]);
      const security: SystemSecurity = {
        firewall: parseOnOff(text(ufw)),
      };
      const selinuxValue = firstLine(text(selinux));
      if (selinuxValue) security.selinux = selinuxValue;
      if (apparmor.ok) security.appArmor = "enabled";
      const lsm = readFileSafe("/sys/kernel/security/lsm").trim();
      if (lsm && !security.appArmor && !security.selinux) security.appArmor = lsm;
      return security;
    }

    if (os === "win32") {
      const [defender, firewall] = await Promise.all([
        this.run(
          "powershell",
          ["-NoProfile", "-NonInteractive", "-Command", "(Get-MpComputerStatus).RealTimeProtectionEnabled"],
          COMMAND_TIMEOUT_MS,
        ),
        this.run(
          "powershell",
          [
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Get-NetFirewallProfile | Select-Object Name,Enabled | ConvertTo-Json -Compress",
          ],
          COMMAND_TIMEOUT_MS,
        ),
      ]);
      return {
        defender: firstLine(text(defender)) || undefined,
        firewall: summarizeWindowsFirewall(text(firewall)),
      };
    }

    return null;
  }

  // MARK: - Dynamic collectors

  private collectMemory(staticMemory: Partial<SystemMemory>): SystemMemory {
    const total = totalmem();
    const free = freemem();
    // "Available" accounts for reclaimable cache/pages; using raw free makes
    // macOS look like it is out of memory (it keeps very little truly free).
    const available = staticMemory.availableBytes ?? free;
    return {
      totalBytes: total,
      freeBytes: free,
      usedBytes: Math.max(0, total - available),
      ...staticMemory,
    };
  }

  private sampleCPUUsage(): { usagePercent?: number; perCoreUsage?: number[] } {
    const current = cpus().map((cpu) => {
      const times = cpu.times;
      return {
        total: times.user + times.nice + times.sys + times.idle + times.irq,
        idle: times.idle,
      };
    });

    let usagePercent: number | undefined;
    let perCoreUsage: number[] | undefined;
    if (this.previousCPU && this.previousCPU.length === current.length) {
      const perCore = current.map((sample, index) => {
        const previous = this.previousCPU?.[index];
        if (!previous) return 0;
        const totalDelta = sample.total - previous.total;
        const idleDelta = sample.idle - previous.idle;
        if (totalDelta <= 0) return 0;
        return round(Math.min(100, Math.max(0, ((totalDelta - idleDelta) / totalDelta) * 100)), 1);
      });
      perCoreUsage = perCore;
      if (perCore.length > 0) {
        usagePercent = round(perCore.reduce((sum, value) => sum + value, 0) / perCore.length, 1);
      }
    }
    this.previousCPU = current;
    return { usagePercent, perCoreUsage };
  }

  private async collectDisks(): Promise<SystemDisk[]> {
    const os = platform();
    if (os === "win32") {
      const result = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID,FileSystem,Size,FreeSpace,DriveType | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const raw = parseJSONValue(text(result));
      const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
      return entries.flatMap((rawEntry) => {
        const entry = asRecord(rawEntry);
        const mount = stringValue(entry?.DeviceID);
        const total = numberValue(entry?.Size);
        const free = numberValue(entry?.FreeSpace);
        if (!mount || total === undefined || free === undefined) return [];
        return [{
          mount,
          filesystem: stringValue(entry?.FileSystem) ?? "unknown",
          type: winDriveType(numberValue(entry?.DriveType)),
          totalBytes: total,
          usedBytes: Math.max(0, total - free),
          freeBytes: free,
        }];
      });
    }

    const result = await this.run("df", ["-kP"], COMMAND_TIMEOUT_MS);
    if (!result.ok) return [];
    const disks = parseDF(text(result));
    return disks.sort((a, b) => {
      if (a.mount === "/") return -1;
      if (b.mount === "/") return 1;
      return a.mount.localeCompare(b.mount);
    });
  }

  private async collectProcesses(): Promise<{ total: number; topCPU: SystemProcess[]; topMemory: SystemProcess[] }> {
    const os = platform();
    if (os === "win32") {
      const result = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-Process | Select-Object Id,ProcessName,CPU,WorkingSet64 | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const raw = parseJSONValue(text(result));
      const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
      const processes: SystemProcess[] = entries.flatMap((rawEntry) => {
        const entry = asRecord(rawEntry);
        const pid = numberValue(entry?.Id);
        const name = stringValue(entry?.ProcessName);
        if (pid === undefined || !name) return [];
        return [{
          pid,
          name,
          memoryBytes: numberValue(entry?.WorkingSet64),
        }];
      });
      return {
        total: processes.length,
        topCPU: processes.slice(0, 12),
        topMemory: [...processes]
          .sort((a, b) => (b.memoryBytes ?? 0) - (a.memoryBytes ?? 0))
          .slice(0, 12),
      };
    }

    const result = await this.run(
      "ps",
      ["-axo", "pid=,pcpu=,pmem=,rss=,user=,comm="],
      COMMAND_TIMEOUT_MS,
    );
    if (!result.ok) return { total: 0, topCPU: [], topMemory: [] };
    return summarizeProcesses(text(result));
  }

  private async collectBattery(): Promise<SystemBattery | null> {
    const os = platform();
    if (os === "darwin") {
      const [pmset, ioreg] = await Promise.all([
        this.run("pmset", ["-g", "batt"], COMMAND_TIMEOUT_MS),
        this.run("ioreg", ["-r", "-c", "AppleSmartBattery", "-w0"], COMMAND_TIMEOUT_MS),
      ]);
      const info = parsePMSetBattery(text(pmset));
      if (!info) return null;
      const details = parseIORegBattery(text(ioreg));
      return {
        present: true,
        ...info,
        cycleCount: details.cycleCount,
        condition: details.condition,
        temperatureC: details.temperatureC,
        healthPercent: details.maxCapacity && details.designCapacity
          ? round((details.maxCapacity / details.designCapacity) * 100, 0)
          : undefined,
      };
    }

    if (os === "linux") {
      const base = "/sys/class/power_supply";
      for (const entry of listDirectory(base)) {
        if (!/^BAT/i.test(entry)) continue;
        const directory = join(base, entry);
        const percent = numberValue(readFileSafe(join(directory, "capacity")).trim());
        const status = readFileSafe(join(directory, "status")).trim();
        const energyNow = numberValue(readFileSafe(join(directory, "energy_now")).trim());
        const energyFull = numberValue(readFileSafe(join(directory, "energy_full")).trim());
        const design = numberValue(readFileSafe(join(directory, "energy_full_design")).trim());
        const powerNow = numberValue(readFileSafe(join(directory, "power_now")).trim());
        let minutesRemaining: number | undefined;
        if (energyNow !== undefined && powerNow && powerNow > 0) {
          minutesRemaining = Math.round((energyNow / powerNow) * 60);
        }
        return {
          present: true,
          percent,
          charging: /charging/i.test(status) && !/discharging/i.test(status),
          state: status || undefined,
          minutesRemaining,
          healthPercent: energyFull && design ? round((energyFull / design) * 100, 0) : undefined,
        };
      }
      return null;
    }

    if (os === "win32") {
      const result = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-CimInstance Win32_Battery | Select-Object -First 1 EstimatedChargeRemaining,BatteryStatus,DesignCapacity,FullChargeCapacity | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const entry = parseJSONRecord(firstLine(text(result)));
      if (!entry) return null;
      const percent = numberValue(entry.EstimatedChargeRemaining);
      const status = numberValue(entry.BatteryStatus);
      return {
        present: true,
        percent,
        charging: status === 2,
        state: winBatteryState(status),
        healthPercent: numberValue(entry.FullChargeCapacity) && numberValue(entry.DesignCapacity)
          ? round((numberValue(entry.FullChargeCapacity)! / numberValue(entry.DesignCapacity)!) * 100, 0)
          : undefined,
      };
    }

    return null;
  }

  private async collectThermal(): Promise<SystemThermal | null> {
    const os = platform();
    if (os === "darwin") {
      const result = await this.run("pmset", ["-g", "therm"], COMMAND_TIMEOUT_MS);
      if (!result.ok) return null;
      const values = parseColonNumberLines(text(result));
      const speedLimit = values.CPU_Speed_Limit;
      const schedulerLimit = values.CPU_Scheduler_Limit;
      if (speedLimit === undefined && schedulerLimit === undefined) return null;
      const pressure = speedLimit !== undefined
        ? speedLimit >= 100 ? "Nominal" : speedLimit >= 80 ? "Fair" : speedLimit >= 50 ? "Serious" : "Critical"
        : undefined;
      return {
        cpuSpeedLimitPercent: speedLimit,
        cpuSchedulerLimitPercent: schedulerLimit,
        pressure,
      };
    }

    if (os === "linux") {
      const base = "/sys/class/thermal";
      const sensors: Array<{ name: string; temperatureC: number }> = [];
      for (const entry of listDirectory(base)) {
        if (!entry.startsWith("thermal_zone")) continue;
        const directory = join(base, entry);
        const raw = numberValue(readFileSafe(join(directory, "temp")).trim());
        if (raw === undefined) continue;
        sensors.push({
          name: readFileSafe(join(directory, "type")).trim() || entry,
          temperatureC: round(raw / 1_000, 1),
        });
      }
      if (sensors.length === 0) return null;
      const hottest = sensors.reduce((max, sensor) => sensor.temperatureC > max ? sensor.temperatureC : max, 0);
      return {
        temperatureC: hottest,
        sensors,
        pressure: hottest >= 95 ? "Critical" : hottest >= 85 ? "Serious" : hottest >= 70 ? "Fair" : "Nominal",
      };
    }

    return null;
  }

  private async collectNetwork(): Promise<SystemNetwork> {
    const interfaces = networkInterfaces();
    const result: SystemNetwork["interfaces"] = [];
    for (const [name, addresses] of Object.entries(interfaces)) {
      if (!addresses || addresses.length === 0) continue;
      result.push({
        name,
        addresses: addresses.map((address) => ({
          address: address.address,
          family: address.family,
          internal: address.internal,
          mac: address.mac,
          netmask: address.netmask,
          cidr: address.cidr ?? undefined,
        })),
      });
    }
    result.sort((a, b) => a.name.localeCompare(b.name));

    const os = platform();
    let defaultGateway: string | undefined;
    let defaultInterface: string | undefined;
    let dnsServers: string[] = [];

    if (os === "darwin") {
      const [route, dns] = await Promise.all([
        this.run("route", ["-n", "get", "default"], COMMAND_TIMEOUT_MS),
        this.run("scutil", ["--dns"], COMMAND_TIMEOUT_MS),
      ]);
      const routeText = text(route);
      defaultGateway = /gateway:\s*(\S+)/.exec(routeText)?.[1];
      defaultInterface = /interface:\s*(\S+)/.exec(routeText)?.[1];
      dnsServers = unique(
        [...text(dns).matchAll(/nameserver\[\d+\]\s*:\s*(\S+)/g)].map((match) => match[1] ?? ""),
      );
    } else if (os === "linux") {
      const route = await this.run("ip", ["route", "show", "default"], COMMAND_TIMEOUT_MS);
      const routeText = firstLine(text(route));
      defaultGateway = /via\s+(\S+)/.exec(routeText ?? "")?.[1];
      defaultInterface = /\bdev\s+(\S+)/.exec(routeText ?? "")?.[1];
      dnsServers = [...readFileSafe("/etc/resolv.conf").matchAll(/^nameserver\s+(\S+)/gm)]
        .map((match) => match[1] ?? "");
      dnsServers = unique(dnsServers);
    } else if (os === "win32") {
      const [route, dns] = await Promise.all([
        this.run("powershell", ["-NoProfile", "-NonInteractive", "-Command", "(Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric | Select-Object -First 1).NextHop"], COMMAND_TIMEOUT_MS),
        this.run("powershell", ["-NoProfile", "-NonInteractive", "-Command", "(Get-DnsClientServerAddress -AddressFamily IPv4).ServerAddresses"], COMMAND_TIMEOUT_MS),
      ]);
      defaultGateway = firstLine(text(route));
      dnsServers = unique(lines(text(dns)));
    }

    return {
      hostname: hostname(),
      interfaces: result,
      defaultGateway,
      defaultInterface,
      dnsServers,
    };
  }

  private async collectMedia(): Promise<SystemMedia[]> {
    const os = platform();
    let media: SystemMedia[] = [];

    if (os === "darwin") {
      const result = await this.run(
        "osascript",
        ["-l", "JavaScript", "-e", NOW_PLAYING_SCRIPT],
        COMMAND_TIMEOUT_MS,
      );
      const payload = parseJSONRecord(firstLine(text(result)));
      const entries = payload?.media;
      if (Array.isArray(entries)) {
        media = entries.flatMap((raw) => normalizeMedia(raw));
      }
      if (media.length === 0) {
        media = await this.collectAppleScriptMedia();
      }
      media = mergeMedia(media, await this.collectMediaAssertions());
      return media.sort(mediaSort);
    }

    if (os === "linux") {
      const playerctl = findExecutable("playerctl");
      if (!playerctl) return [];
      const listed = await this.run(playerctl, ["-l"], COMMAND_TIMEOUT_MS);
      const players = lines(text(listed));
      const format = "{{playerName}}\t{{status}}\t{{title}}\t{{artist}}\t{{album}}\t{{position}}\t{{mpris:length}}";
      const results = await Promise.all(
        players.map(async (player) => {
          const result = await this.run(
            playerctl,
            ["--player", player, "metadata", "--format", format],
            COMMAND_TIMEOUT_MS,
          );
          return parsePlayerctlMedia(text(result));
        }),
      );
      return results.flat().sort(mediaSort);
    }

    return [];
  }

  /**
   * Applies a playback or output-volume command, then returns the fresh media
   * and audio state so clients can update without a full system refresh.
   */
  /** Alias used by the HTTP layer. */
  control(action: string, value?: number): Promise<MediaControlResult> {
    return this.controlMedia(action, value);
  }

  async controlMedia(action: string, value?: number): Promise<MediaControlResult> {
    const os = platform();

    if (action === "volume") {
      const percent = Math.round(Math.min(100, Math.max(0, value ?? 50)));
      await this.setSystemVolume(percent);
    } else if (action === "mute") {
      await this.setSystemMuted((value ?? 0) !== 0);
    } else {
      const command = MEDIA_COMMANDS[action];
      if (command === undefined) {
        throw new MediaControlError(`Unknown media action: ${action}`, 400);
      }
      let controlled = false;
      if (os === "darwin") {
        const result = await this.run(
          "osascript",
          ["-l", "JavaScript", "-e", MEDIA_CONTROL_SCRIPT, String(command)],
          COMMAND_TIMEOUT_MS,
        );
        const payload = parseJSONRecord(firstLine(text(result)));
        controlled = payload?.ok === true;
        if (!controlled) {
          controlled = await this.controlAppleScriptMedia(action);
        }
      } else if (os === "linux") {
        const playerctl = findExecutable("playerctl");
        if (playerctl) {
          const commandName = action === "toggle" ? "play-pause" : action === "back15" ? "previous" : action === "forward15" ? "next" : action;
          const result = await this.run(playerctl, [commandName], COMMAND_TIMEOUT_MS);
          controlled = result.ok;
        }
      }
      if (!controlled) {
        throw new MediaControlError("Nothing is playing", 409);
      }
    }

    // Give the player a moment to publish the new state before reading it.
    await new Promise((resolve) => setTimeout(resolve, 450));
    const [media, audio] = await Promise.all([this.collectMedia(), this.collectAudio()]);
    if (this.snapshotCache) {
      this.snapshotCache.value = {
        ...this.snapshotCache.value,
        media,
        audio,
        generatedAt: Date.now(),
      };
    }
    return { media, audio };
  }

  /** Adds or removes media type controls for players without MediaRemote. */
  private async controlAppleScriptMedia(action: string): Promise<boolean> {
    const verb = action === "toggle"
      ? "playpause"
      : action === "play"
        ? "play"
        : action === "pause"
          ? "pause"
          : action === "next"
            ? "next track"
            : action === "previous"
              ? "previous track"
              : action === "stop"
                ? "stop"
                : null;
    if (!verb) return false;

    const script = String.raw`set did to false
if application "Music" is running then
  tell application "Music"
    if player state is not stopped then
      ${verb}
      set did to true
    end if
  end tell
end if
if not did and application "Spotify" is running then
  tell application "Spotify"
    if player state is not stopped then
      ${verb}
      set did to true
    end if
  end tell
end if
return did`;
    const result = await this.run("osascript", ["-e", script], COMMAND_TIMEOUT_MS);
    return /true/i.test(firstLine(text(result)) ?? "");
  }

  private async collectAudio(): Promise<SystemAudio | null> {
    const os = platform();
    if (os === "darwin") {
      const result = await this.run("osascript", ["-e", "get volume settings"], COMMAND_TIMEOUT_MS);
      const textValue = text(result);
      const volume = numberValue(/output volume:(\d+)/.exec(textValue)?.[1]);
      const muted = /output muted:(true|false)/i.exec(textValue)?.[1];
      if (volume === undefined) return null;
      return {
        volumePercent: volume,
        muted: muted?.toLowerCase() === "true",
        controllable: true,
      };
    }

    if (os === "linux") {
      const pactl = findExecutable("pactl");
      if (!pactl) return null;
      const [volumeResult, muteResult] = await Promise.all([
        this.run(pactl, ["get-sink-volume", "@DEFAULT_SINK@"], COMMAND_TIMEOUT_MS),
        this.run(pactl, ["get-sink-mute", "@DEFAULT_SINK@"], COMMAND_TIMEOUT_MS),
      ]);
      const volume = numberValue(/(\d+)%/.exec(text(volumeResult))?.[1]);
      const muted = /\bMute:\s*(yes|no)/i.exec(text(muteResult))?.[1];
      if (volume === undefined) return null;
      return {
        volumePercent: Math.min(100, volume),
        muted: muted?.toLowerCase() === "yes",
        controllable: true,
      };
    }

    return null;
  }

  private async setSystemVolume(percent: number): Promise<void> {
    const os = platform();
    if (os === "darwin") {
      await this.run("osascript", ["-e", `set volume output volume ${percent}`], COMMAND_TIMEOUT_MS);
      return;
    }
    if (os === "linux") {
      const pactl = findExecutable("pactl");
      if (pactl) {
        await this.run(pactl, ["set-sink-volume", "@DEFAULT_SINK@", `${percent}%`], COMMAND_TIMEOUT_MS);
      }
    }
  }

  private async setSystemMuted(muted: boolean): Promise<void> {
    const os = platform();
    if (os === "darwin") {
      await this.run(
        "osascript",
        ["-e", `set volume output muted ${muted ? "true" : "false"}`],
        COMMAND_TIMEOUT_MS,
      );
      return;
    }
    if (os === "linux") {
      const pactl = findExecutable("pactl");
      if (pactl) {
        await this.run(
          pactl,
          ["set-sink-mute", "@DEFAULT_SINK@", muted ? "1" : "0"],
          COMMAND_TIMEOUT_MS,
        );
      }
    }
  }

  /** Older macOS versions without MediaRemote still expose the big players. */
  private async collectAppleScriptMedia(): Promise<SystemMedia[]> {
    const result = await this.run("osascript", ["-e", APPLESCRIPT_MEDIA_SCRIPT], COMMAND_TIMEOUT_MS);
    const media: SystemMedia[] = [];
    for (const line of lines(text(result))) {
      const [app, state, title, artist, album, position, duration] = line.split("\t");
      if (!app) continue;
      const isSpotify = app.trim().toLowerCase() === "spotify";
      const elapsed = numberValue(position);
      const total = numberValue(duration);
      media.push({
        app: app.trim(),
        title: title?.trim() || undefined,
        artist: artist?.trim() || undefined,
        album: album?.trim() || undefined,
        state: state?.toLowerCase().includes("play") ? "playing" : "paused",
        elapsedSeconds: elapsed,
        durationSeconds: total === undefined ? undefined : isSpotify ? total / 1_000 : total,
        source: "applescript",
        supportedCommands: [0, 1, 2, 4, 5],
      });
    }
    return media;
  }

  /**
   * `pmset` lists media assertions for browsers and video apps that do not
   * publish a MediaRemote item. It tells us the owning app and whether audio or
   * video is active, even without track metadata.
   */
  private async collectMediaAssertions(): Promise<SystemMedia[]> {
    const result = await this.run("pmset", ["-g", "assertions"], COMMAND_TIMEOUT_MS);
    if (!result.ok) return [];
    const byApp = new Map<string, SystemMedia>();
    for (const line of text(result).split(/\r?\n/)) {
      const match = line.match(/pid\s+\d+\(([^)]+)\):.*?(Playing audio|Video Wake Lock)/);
      if (!match?.[1]) continue;
      const app = match[1].trim();
      if (!app) continue;
      const key = app.toLowerCase();
      const kind = /video wake lock/i.test(match[2] ?? "") ? "video" : "audio";
      const existing = byApp.get(key);
      if (existing) {
        // An app can hold both audio and video assertions; video is the more
        // useful label for a browser or player.
        if (kind === "video") existing.kind = "video";
        continue;
      }
      byApp.set(key, {
        app,
        state: "playing",
        kind,
        source: "assertion",
      });
    }
    return [...byApp.values()];
  }

  private async collectListeningPorts(): Promise<SystemPort[]> {
    const os = platform();
    if (os === "darwin") {
      const result = await this.run(
        "lsof",
        ["-nP", "-iTCP", "-sTCP:LISTEN"],
        COMMAND_TIMEOUT_MS,
      );
      if (!result.ok && !text(result)) return [];
      return parseLsofPorts(text(result));
    }

    if (os === "linux") {
      let result = await this.run("ss", ["-ltnp"], COMMAND_TIMEOUT_MS);
      if (!result.ok) result = await this.run("netstat", ["-ltnp"], COMMAND_TIMEOUT_MS);
      return parseSSPorts(text(result));
    }

    if (os === "win32") {
      const result = await this.run(
        "powershell",
        [
          "-NoProfile",
          "-NonInteractive",
          "-Command",
          "Get-NetTCPConnection -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess | ConvertTo-Json -Compress",
        ],
        COMMAND_TIMEOUT_MS,
      );
      const raw = parseJSONValue(text(result));
      const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
      return entries.flatMap((rawEntry) => {
        const entry = asRecord(rawEntry);
        const port = numberValue(entry?.LocalPort);
        if (port === undefined) return [];
        return [{
          port,
          protocol: "tcp" as const,
          address: stringValue(entry?.LocalAddress),
          pid: numberValue(entry?.OwningProcess),
        }];
      });
    }

    return [];
  }

  private async collectDocker(): Promise<SystemDocker | null> {
    const now = Date.now();
    if (this.lastDocker && now - this.lastDocker.at < 10_000) return this.lastDocker.value;

    const path = findExecutable("docker");
    if (!path) {
      this.lastDocker = { at: now, value: null };
      return null;
    }

    const [versionResult, psResult] = await Promise.all([
      this.run(path, ["--version"], COMMAND_TIMEOUT_MS),
      this.run(path, ["ps", "--format", "{{json .}}"], COMMAND_TIMEOUT_MS),
    ]);
    const containers = lines(text(psResult)).flatMap((line) => {
      const entry = parseJSONRecord(line);
      if (!entry) return [];
      const id = stringValue(entry.ID);
      const name = stringValue(entry.Names);
      if (!id || !name) return [];
      return [{
        id,
        name,
        image: stringValue(entry.Image) ?? "",
        state: stringValue(entry.State) ?? "",
        status: stringValue(entry.Status) ?? "",
        ports: stringValue(entry.Ports),
        created: stringValue(entry.CreatedAt),
      }];
    });
    const value: SystemDocker = {
      available: psResult.ok,
      version: parseDockerVersion(text(versionResult)),
      running: containers.filter((container) => /^running$/i.test(container.state)).length,
      containers,
    };
    this.lastDocker = { at: now, value };
    return value;
  }

  // MARK: - Command helper

  private run(
    command: string,
    args: string[],
    timeoutMs = COMMAND_TIMEOUT_MS,
    env?: NodeJS.ProcessEnv,
  ): Promise<CommandResult> {
    return this.runner(command, args, timeoutMs, env).catch(() => ({
      ok: false,
      stdout: "",
      stderr: "",
    }));
  }
}

// MARK: - Parsing helpers

export function platformName(): string {
  switch (platform()) {
    case "darwin": return "macOS";
    case "linux": return "Linux";
    case "win32": return "Windows";
    default: return type();
  }
}

function text(result: CommandResult | null): string {
  if (!result) return "";
  return result.stdout || result.stderr;
}

function firstLine(value: string): string | undefined {
  const line = value.split(/\r?\n/).map((entry) => entry.trim()).find(Boolean);
  return line || undefined;
}

function lines(value: string): string[] {
  return value
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function unique(values: string[]): string[] {
  return [...new Set(values.filter(Boolean))];
}

function round(value: number, decimals = 1): number {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value.trim());
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function stringValue(value: unknown): string | undefined {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  return undefined;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" ? (value as Record<string, unknown>) : null;
}

function parseJSON(value: string): Record<string, unknown> | null {
  const trimmed = value.trim();
  if (!trimmed.startsWith("{")) return null;
  try {
    return asRecord(JSON.parse(trimmed));
  } catch {
    return null;
  }
}

function parseJSONRecord(value: string | undefined): Record<string, unknown> | null {
  if (!value) return null;
  try {
    return asRecord(JSON.parse(value));
  } catch {
    return null;
  }
}

function firstObject(value: unknown): Record<string, unknown> | null {
  if (!Array.isArray(value)) return null;
  return asRecord(value[0]);
}

function parseKeyValueLines(value: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of lines(value)) {
    const index = line.indexOf(":");
    if (index <= 0) continue;
    result[line.slice(0, index).trim()] = line.slice(index + 1).trim();
  }
  return result;
}

function parseJSONValue(value: string): unknown {
  try {
    return JSON.parse(value.trim());
  } catch {
    return null;
  }
}

function readFileSafe(path: string): string {
  try {
    return readFileSync(path, "utf8");
  } catch {
    try {
      return readFileSync(path, "latin1");
    } catch {
      return "";
    }
  }
}

function listDirectory(path: string): string[] {
  try {
    return readdirSync(path).filter((entry) => !entry.startsWith("."));
  } catch {
    return [];
  }
}

function safeUsername(): string | undefined {
  try {
    return userInfo().username;
  } catch {
    return undefined;
  }
}

function safeCwd(): string | undefined {
  try {
    return process.cwd();
  } catch {
    return undefined;
  }
}

function fileSize(path: string | undefined): number | undefined {
  if (!path) return undefined;
  try {
    return statSync(path).size;
  } catch {
    return undefined;
  }
}

function cpuModel(): string | undefined {
  return cpus()[0]?.model;
}

function parseOSRelease(value: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of lines(value)) {
    const match = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!match?.[1]) continue;
    result[match[1]] = (match[2] ?? "").replace(/^["']|["']$/g, "");
  }
  return result;
}

function parseLinuxCPUModel(cpuinfo: string): string | undefined {
  const match = cpuinfo.match(/^model name\s*:\s*(.+)$/m) ?? cpuinfo.match(/^Hardware\s*:\s*(.+)$/m);
  return match?.[1]?.trim();
}

function parseLinuxCPUVendor(cpuinfo: string): string | undefined {
  return cpuinfo.match(/^vendor_id\s*:\s*(.+)$/m)?.[1]?.trim();
}

function parseLinuxPhysicalCores(cpuinfo: string): number | undefined {
  const pairs = new Set<string>();
  let physicalID = "0";
  let coreID: string | undefined;
  for (const line of cpuinfo.split(/\r?\n/)) {
    const field = line.split(":")[0]?.trim();
    const value = line.slice(line.indexOf(":") + 1).trim();
    if (field === "physical id") physicalID = value;
    if (field === "core id") coreID = value;
    if (coreID !== undefined && field === "core id") pairs.add(`${physicalID}:${coreID}`);
  }
  return pairs.size || undefined;
}

function parseMemInfo(value: string): Partial<SystemMemory> {
  const fields: Record<string, number> = {};
  for (const line of lines(value)) {
    const match = line.match(/^(\S+):\s+(\d+)\s*kB/i);
    if (!match?.[1] || !match[2]) continue;
    fields[match[1]] = Number.parseInt(match[2], 10) * 1_024;
  }
  return {
    availableBytes: fields.MemAvailable,
    activeBytes: fields.Active,
    inactiveBytes: fields.Inactive,
    wiredBytes: fields.Unevictable ?? fields.Wired,
    cachedBytes: fields.Cached,
    compressedBytes: fields.SReclaimable,
    swapTotalBytes: fields.SwapTotal,
    swapFreeBytes: fields.SwapFree,
    swapUsedBytes: fields.SwapTotal !== undefined && fields.SwapFree !== undefined
      ? fields.SwapTotal - fields.SwapFree
      : undefined,
  };
}

function parseVMStat(value: string): Partial<SystemMemory> {
  const pageSize = Number.parseInt(/page size of (\d+) bytes/.exec(value)?.[1] ?? "", 10);
  if (!Number.isFinite(pageSize)) return {};
  const pages: Record<string, number> = {};
  for (const line of lines(value)) {
    const match = line.match(/^([^:]+):\s+(\d+)\.?$/);
    if (!match?.[1] || !match[2]) continue;
    pages[match[1].trim()] = Number.parseInt(match[2], 10);
  }
  const bytes = (key: string): number | undefined => {
    const count = pages[key];
    return count === undefined ? undefined : count * pageSize;
  };
  return {
    freeBytes: bytes("Pages free"),
    activeBytes: bytes("Pages active"),
    inactiveBytes: bytes("Pages inactive"),
    wiredBytes: bytes("Pages wired down"),
    compressedBytes: bytes("Pages occupied by compressor"),
    cachedBytes: bytes("Pages purgeable"),
    availableBytes: (bytes("Pages free") ?? 0) + (bytes("Pages inactive") ?? 0),
  };
}

function parseSwapUsage(value: string): { total?: number; used?: number; free?: number } {
  const match = value.match(/total\s*=\s*([\d.]+)([MG])\s+used\s*=\s*([\d.]+)([MG])\s+free\s*=\s*([\d.]+)([MG])/i);
  if (!match) return {};
  const size = (amount: string | undefined, unit: string | undefined): number | undefined => {
    const parsed = Number.parseFloat(amount ?? "");
    if (!Number.isFinite(parsed)) return undefined;
    return parsed * (unit?.toUpperCase() === "G" ? 1_073_741_824 : 1_048_576);
  };
  const total = size(match[1], match[2]);
  const used = size(match[3], match[4]);
  const free = size(match[5], match[6]);
  return {
    total: total === undefined ? undefined : Math.round(total),
    used: used === undefined ? undefined : Math.round(used),
    free: free === undefined ? undefined : Math.round(free),
  };
}

function normalizeMedia(raw: unknown): SystemMedia[] {
  const entry = asRecord(raw);
  const app = stringValue(entry?.app);
  if (!app) return [];

  const stateValue = stringValue(entry?.state)?.toLowerCase();
  const state = stateValue === "playing" || stateValue === "paused" || stateValue === "stopped"
    ? stateValue
    : undefined;
  const playbackRate = numberValue(entry?.playbackRate);
  const kindValue = stringValue(entry?.kind)?.toLowerCase();
  const kind = kindValue === "audio" || kindValue === "video" ? kindValue : undefined;
  const commands = Array.isArray(entry?.supportedCommands)
    ? entry.supportedCommands
        .map((command) => numberValue(command))
        .filter((command): command is number => command !== undefined)
    : [];
  // Some players briefly report no command list while still accepting the
  // basic transport commands MediaRemote exposes.
  if (commands.length === 0) commands.push(0, 1, 2);

  return [{
    app,
    bundleID: stringValue(entry?.bundleID),
    title: stringValue(entry?.title),
    artist: stringValue(entry?.artist),
    album: stringValue(entry?.album),
    state: state ?? (playbackRate === 0 ? "paused" : playbackRate === undefined ? undefined : "playing"),
    elapsedSeconds: numberValue(entry?.elapsedSeconds),
    durationSeconds: numberValue(entry?.durationSeconds),
    playbackRate,
    kind,
    source: "mediaremote",
    supportedCommands: commands,
  }];
}

function parsePlayerctlMedia(value: string): SystemMedia[] {
  const [app, status, title, artist, album, position, length] = value.split("\t");
  if (!app?.trim() || /^stopped$/i.test(status?.trim() ?? "")) return [];
  const positionMicros = numberValue(position);
  const lengthMicros = numberValue(length);
  return [{
    app: app.trim(),
    title: title?.trim() || undefined,
    artist: artist?.trim() || undefined,
    album: album?.trim() || undefined,
    state: /^playing$/i.test(status?.trim() ?? "") ? "playing" : "paused",
    elapsedSeconds: positionMicros === undefined ? undefined : round(positionMicros / 1_000_000, 1),
    durationSeconds: lengthMicros === undefined ? undefined : round(lengthMicros / 1_000_000, 1),
    source: "playerctl",
    supportedCommands: [0, 1, 2, 4, 5],
  }];
}

function mergeMedia(primary: SystemMedia[], extra: SystemMedia[]): SystemMedia[] {
  const byApp = new Map<string, SystemMedia>();
  for (const item of [...primary, ...extra]) {
    const key = item.app.trim().toLowerCase();
    if (!key) continue;
    const existing = byApp.get(key);
    if (!existing) {
      byApp.set(key, item);
      continue;
    }
    existing.state = item.state === "playing" ? "playing" : item.state ?? existing.state;
    existing.kind = existing.kind ?? item.kind;
    if (!existing.title && item.title) existing.title = item.title;
    if (!existing.artist && item.artist) existing.artist = item.artist;
    if (!existing.album && item.album) existing.album = item.album;
  }
  return [...byApp.values()];
}

function mediaSort(left: SystemMedia, right: SystemMedia): number {
  const rank = (value: SystemMedia): number => value.state === "playing" ? 0 : value.state === "paused" ? 1 : 2;
  const difference = rank(left) - rank(right);
  if (difference !== 0) return difference;
  return left.app.localeCompare(right.app);
}

export function parseDF(value: string): SystemDisk[] {
  const disks: SystemDisk[] = [];
  for (const line of value.split(/\r?\n/).slice(1)) {
    const match = line.match(/^(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)%\s+(.+)$/);
    if (!match) continue;
    const filesystem = match[1] ?? "";
    const totalKiB = Number.parseInt(match[2] ?? "", 10);
    const usedKiB = Number.parseInt(match[3] ?? "", 10);
    const freeKiB = Number.parseInt(match[4] ?? "", 10);
    const mount = (match[6] ?? "").trim();
    if (!mount || !Number.isFinite(totalKiB) || totalKiB === 0) continue;
    if (/^(devfs|map|none|udev|tmpfs|overlay)$/i.test(filesystem) && mount !== "/") continue;
    if (filesystem === "devfs") continue;
    disks.push({
      mount,
      filesystem,
      totalBytes: totalKiB * 1_024,
      usedBytes: usedKiB * 1_024,
      freeBytes: freeKiB * 1_024,
      readOnly: false,
      removable: mount.startsWith("/Volumes/") || mount.startsWith("/media/") || mount.startsWith("/run/media/"),
    });
  }
  return disks;
}

export function parseBrewVersions(
  value: string,
  kind: "formula" | "cask",
  outdated: Set<string>,
): SystemBrewPackage[] {
  return lines(value).flatMap((line) => {
    const parts = line.split(/\s+/);
    const name = parts[0];
    if (!name) return [];
    return [{
      name,
      version: parts.slice(1).join(" ") || "unknown",
      kind,
      outdated: outdated.has(name),
    }];
  });
}

export function summarizeProcesses(value: string): {
  total: number;
  topCPU: SystemProcess[];
  topMemory: SystemProcess[];
} {
  const processes: SystemProcess[] = [];
  for (const line of value.split(/\r?\n/)) {
    const match = line.match(/^\s*(\d+)\s+([\d.]+)\s+([\d.]+)\s+(\d+)\s+(\S+)\s+(.+)$/);
    if (!match) continue;
    const pid = Number.parseInt(match[1] ?? "", 10);
    const cpu = Number.parseFloat(match[2] ?? "");
    const memoryPercent = Number.parseFloat(match[3] ?? "");
    const rss = Number.parseInt(match[4] ?? "", 10);
    const user = match[5];
    const command = (match[6] ?? "").trim();
    if (!Number.isFinite(pid) || !command) continue;
    processes.push({
      pid,
      name: basename(command) || command,
      command,
      user,
      cpuPercent: Number.isFinite(cpu) ? round(cpu, 1) : undefined,
      memoryPercent: Number.isFinite(memoryPercent) ? round(memoryPercent, 1) : undefined,
      memoryBytes: Number.isFinite(rss) ? rss * 1_024 : undefined,
    });
  }

  const topCPU = [...processes]
    .sort((a, b) => (b.cpuPercent ?? 0) - (a.cpuPercent ?? 0))
    .slice(0, 12);
  const topMemory = [...processes]
    .sort((a, b) => (b.memoryBytes ?? 0) - (a.memoryBytes ?? 0))
    .slice(0, 12);

  return { total: processes.length, topCPU, topMemory };
}

function parsePMSetBattery(value: string): Partial<SystemBattery> | null {
  const line = value.split(/\r?\n/).find((entry) => /InternalBattery|Battery/.test(entry) && /%/.test(entry));
  if (!line) return null;
  const percent = Number.parseInt(/(\d+)%/.exec(line)?.[1] ?? "", 10);
  const state = /;\s*([^;]+);/.exec(line)?.[1]?.trim();
  const remaining = /(\d+):(\d+)\s+remaining/.exec(line);
  const minutesRemaining = remaining
    ? Number.parseInt(remaining[1] ?? "0", 10) * 60 + Number.parseInt(remaining[2] ?? "0", 10)
    : undefined;
  return {
    percent: Number.isFinite(percent) ? percent : undefined,
    charging: /\bcharging\b|charged|AC Power/i.test(line),
    state,
    minutesRemaining,
  };
}

function parseIORegBattery(value: string): {
  maxCapacity?: number;
  designCapacity?: number;
  cycleCount?: number;
  condition?: string;
  temperatureC?: number;
} {
  const read = (key: string): number | undefined => {
    const match = new RegExp(`"${key}"\\s*=\\s*(\\d+)`).exec(value);
    const parsed = Number.parseInt(match?.[1] ?? "", 10);
    return Number.isFinite(parsed) ? parsed : undefined;
  };
  const health = /"BatteryHealth"\s*=\s*"([^"]+)"/.exec(value)?.[1];
  // `MaxCapacity` on modern Macs is a percentage; the raw mAh value lives in
  // AppleRawMaxCapacity or in the nested BatteryData dictionary.
  const capacity = read("AppleRawMaxCapacity") ?? read("FullChargeCapacity");
  const design = read("DesignCapacity");
  const temperature = read("Temperature");
  const permanentFailure = read("PermanentFailureStatus");
  return {
    maxCapacity: capacity,
    designCapacity: design,
    cycleCount: read("CycleCount"),
    condition: health ?? (permanentFailure === 0 ? "Good" : undefined),
    temperatureC: temperature ? round(temperature / 10 - 273.15, 1) : undefined,
  };
}

function parseOnOff(value: string): boolean | string | undefined {
  const lower = value.toLowerCase();
  if (!lower.trim()) return undefined;
  if (lower.includes("disabled") || lower.includes(" off") || lower.includes("inactive")) return false;
  if (lower.includes("enabled") || lower.includes(" on") || lower.includes("active")) return true;
  return value.trim().slice(0, 120) || undefined;
}

function parseColonNumberLines(value: string): Record<string, number> {
  const result: Record<string, number> = {};
  for (const line of lines(value)) {
    const match = line.match(/^([A-Za-z0-9_]+)\s*=\s*(\d+)/);
    if (!match?.[1] || !match[2]) continue;
    result[match[1]] = Number.parseInt(match[2], 10);
  }
  return result;
}

function parseDesktopEntry(value: string): Record<string, string> {
  const result: Record<string, string> = {};
  for (const line of lines(value)) {
    if (line.startsWith("#") || line.startsWith("[")) continue;
    const index = line.indexOf("=");
    if (index <= 0) continue;
    result[line.slice(0, index).trim()] = line.slice(index + 1).trim();
  }
  return result;
}

function cleanVersion(name: string, value: string): string {
  const line = lines(value).find((entry) => !/^(usage|help|available commands)/i.test(entry)) ?? "";
  let version = line.replace(/\s+/g, " ").trim();
  const labelled = /^(?:Client Version|Server Version|clientVersion|serverVersion)\s*:\s*(.+)$/i.exec(version);
  if (labelled?.[1]) version = labelled[1].trim();
  if (/^v?\d/.test(version)) {
    const first = version.split(/\s+/)[0];
    if (first) version = first;
  }
  if (version.length > 120) version = `${version.slice(0, 117)}…`;
  return version || "installed";
}

function parseDockerVersion(value: string): string | undefined {
  return /Docker version\s+([^,\s]+)/i.exec(value)?.[1] ?? firstLine(value);
}

function parseLsofPorts(value: string): SystemPort[] {
  const ports: SystemPort[] = [];
  const seen = new Set<string>();
  for (const line of value.split(/\r?\n/)) {
    const match = line.match(/^(\S+)\s+(\d+)\s+\S+.*\sTCP\s+(\S+)\s+\(LISTEN\)/);
    if (!match) continue;
    const process = match[1] ?? "";
    const pid = Number.parseInt(match[2] ?? "", 10);
    const name = match[3] ?? "";
    const separator = name.lastIndexOf(":");
    if (separator < 0) continue;
    const port = Number.parseInt(name.slice(separator + 1), 10);
    if (!Number.isFinite(port)) continue;
    const key = `${port}:${process}:${pid}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ports.push({
      port,
      protocol: "tcp",
      address: name.slice(0, separator),
      process,
      pid: Number.isFinite(pid) ? pid : undefined,
    });
  }
  return ports.sort((a, b) => a.port - b.port);
}

function parseSSPorts(value: string): SystemPort[] {
  const ports: SystemPort[] = [];
  const seen = new Set<string>();
  for (const line of value.split(/\r?\n/)) {
    const columns = line.trim().split(/\s+/);
    if (columns[0] !== "LISTEN") continue;
    const local = columns[3];
    if (!local) continue;
    const separator = local.lastIndexOf(":");
    if (separator < 0) continue;
    const port = Number.parseInt(local.slice(separator + 1), 10);
    if (!Number.isFinite(port)) continue;
    const processMatch = /users:\(\("([^"]+)",pid=(\d+)/.exec(line);
    const process = processMatch?.[1];
    const pid = processMatch?.[2] ? Number.parseInt(processMatch[2], 10) : undefined;
    const key = `${port}:${process ?? ""}:${pid ?? 0}`;
    if (seen.has(key)) continue;
    seen.add(key);
    ports.push({
      port,
      protocol: "tcp",
      address: local.slice(0, separator),
      process,
      pid,
    });
  }
  return ports.sort((a, b) => a.port - b.port);
}

function summarizeWindowsFirewall(value: string): boolean | string | undefined {
  if (!value.trim()) return undefined;
  const raw = parseJSONValue(value);
  const entries = Array.isArray(raw) ? raw : raw ? [raw] : [];
  if (entries.length === 0) return undefined;
  const enabled = entries.every((entry) => {
    const record = asRecord(entry);
    return record?.Enabled === true || record?.Enabled === 1;
  });
  return enabled;
}

function winDriveType(value: number | undefined): string | undefined {
  switch (value) {
    case 2: return "removable";
    case 3: return "fixed";
    case 4: return "network";
    case 5: return "optical";
    case 6: return "ram";
    default: return undefined;
  }
}

function winBatteryState(value: number | undefined): string | undefined {
  switch (value) {
    case 1: return "discharging";
    case 2: return "on AC";
    case 3: return "fully charged";
    case 4: return "low";
    case 5: return "critical";
    case 6: return "charging";
    case 7: return "charging, high";
    case 8: return "charging, low";
    case 9: return "charging, critical";
    case 11: return "partially charged";
    default: return undefined;
  }
}

export function findExecutable(name: string, extraDirectories: string[] = []): string | undefined {
  const extensions = process.platform === "win32"
    ? ["", ...(process.env.PATHEXT ?? ".EXE;.CMD;.BAT").split(";").filter(Boolean)]
    : [""];
  const directories = [
    ...(process.env.PATH ?? "").split(delimiter),
    ...extraDirectories,
  ].filter(Boolean);

  for (const directory of directories) {
    for (const extension of extensions) {
      const candidate = join(directory, `${name}${extension}`);
      try {
        accessSync(candidate, process.platform === "win32" ? constants.F_OK : constants.X_OK);
        return candidate;
      } catch {
        // Try the next candidate.
      }
    }
  }
  return undefined;
}

// Re-exported for tests that want to inspect a parsed system_profiler payload.
export { parseJSONValue };
