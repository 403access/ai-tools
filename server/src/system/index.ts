import { arch, cpus, hostname, loadavg, platform, release, uptime } from "node:os";
import { HUB_VERSION } from "../config.ts";
import type { MediaControlResult, SystemAppDetail, SystemInfo } from "../types.ts";
import { AppActionError, collectAppDetail, performAppAction } from "./appDetail.ts";
import { collectApps } from "./apps.ts";
import { collectAudio, setSystemMuted, setSystemVolume } from "./audio.ts";
import { collectBattery } from "./battery.ts";
import { defaultRunner } from "./commands.ts";
import { DEFAULT_CACHE_TTL_MS, DEFAULT_STATIC_TTL_MS } from "./constants.ts";
import { DockerCollector } from "./docker.ts";
import { collectDisplays } from "./displays.ts";
import { collectHomebrew } from "./homebrew.ts";
import { collectHardware, collectOS } from "./host.ts";
import { MediaControlError, collectMedia, controlPlayback } from "./media.ts";
import { collectMemory } from "./memory.ts";
import { collectListeningPorts, collectNetwork } from "./network.ts";
import { collectProcesses } from "./processes.ts";
import { collectRuntimes } from "./runtimes.ts";
import { collectSecurity } from "./security.ts";
import { collectDisks } from "./storage.ts";
import { collectThermal } from "./thermal.ts";
import type { CommandRunner, StaticInfo, SystemInfoOptions } from "./types.ts";
import { fileSize, platformName, round, safeCwd } from "./util.ts";

/**
 * Collects a full snapshot of the machine running the hub. Dynamic facts (load,
 * memory, disks, processes) are refreshed on every request; expensive static
 * facts (installed apps, Homebrew, toolchain versions, displays) are cached.
 *
 * The individual collectors live in sibling modules; this class only owns the
 * caches, CPU sampling and the snapshot shape.
 */
export class SystemInfoService {
  private readonly runner: CommandRunner;
  private readonly staticTTLMs: number;
  private readonly cacheTTLMs: number;
  private readonly hub: SystemInfoOptions["hub"];
  private readonly docker = new DockerCollector();

  private staticCache: { at: number; value: StaticInfo } | null = null;
  private staticInFlight: Promise<StaticInfo> | null = null;
  private snapshotCache: { at: number; value: SystemInfo } | null = null;
  private snapshotInFlight: Promise<SystemInfo> | null = null;
  private previousCPU: Array<{ total: number; idle: number }> | null = null;

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
        collectDisks(this.runner),
        collectProcesses(this.runner),
        collectBattery(this.runner),
        collectThermal(this.runner),
        collectListeningPorts(this.runner),
        this.docker.collect(this.runner),
        collectNetwork(this.runner),
        collectMedia(this.runner),
        collectAudio(this.runner),
      ]);

    const cpuUsage = this.sampleCPUUsage();
    const memory = collectMemory(staticInfo.memory);
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
      collectOS(this.runner, info),
      collectHardware(this.runner, info),
      collectApps(this.runner).then((apps) => {
        info.apps = apps;
      }),
      collectHomebrew(this.runner).then((brew) => {
        info.homebrew = brew;
      }),
      collectRuntimes(this.runner).then((runtimes) => {
        info.runtimes = runtimes;
      }),
      collectDisplays(this.runner).then((displays) => {
        info.displays = displays;
      }),
      collectSecurity(this.runner).then((security) => {
        info.security = security;
      }),
    ];

    await Promise.allSettled(tasks);
    return info;
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

  /** Alias used by the HTTP layer. */
  control(action: string, value?: number): Promise<MediaControlResult> {
    return this.controlMedia(action, value);
  }

  /**
   * Detailed inventory for one installed app. Only paths from the current
   * snapshot are accepted, so clients cannot use this to inspect arbitrary
   * files on the host.
   */
  async appDetail(path: string): Promise<SystemAppDetail | null> {
    const snapshot = await this.snapshot(false);
    const app = snapshot.apps.find((entry) => entry.path === path);
    if (!app) return null;
    return collectAppDetail(this.runner, app);
  }

  /** Runs a management action for an app and returns the refreshed detail. */
  async appAction(
    path: string,
    action: string,
    target?: string,
  ): Promise<SystemAppDetail> {
    const detail = await this.appDetail(path);
    if (!detail) throw new AppActionError("Unknown application", 404);
    return performAppAction(this.runner, detail, action, target);
  }

  /**
   * Applies a playback or output-volume command, then returns the fresh media
   * and audio state so clients can update without a full system refresh.
   */
  async controlMedia(action: string, value?: number): Promise<MediaControlResult> {
    if (action === "volume") {
      const percent = Math.round(Math.min(100, Math.max(0, value ?? 50)));
      await setSystemVolume(this.runner, percent);
    } else if (action === "mute") {
      await setSystemMuted(this.runner, (value ?? 0) !== 0);
    } else {
      const controlled = await controlPlayback(this.runner, action);
      if (!controlled) {
        throw new MediaControlError("Nothing is playing", 409);
      }
    }

    // Give the player a moment to publish the new state before reading it.
    await new Promise((resolve) => setTimeout(resolve, 450));
    const [media, audio] = await Promise.all([
      collectMedia(this.runner),
      collectAudio(this.runner),
    ]);
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
}
