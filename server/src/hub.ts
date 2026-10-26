import { type HubConfig } from "./config.ts";
import { HubDB } from "./db.ts";
import {
  OpenCodeClient,
  discoverOpenCode,
  fetchGoUsage,
  type OpenCodeLocation,
} from "./opencode.ts";
import type {
  AgentInfo,
  ConnectedDevice,
  FileDiff,
  HubEvent,
  HubHealth,
  MessagesResponse,
  ModelInfo,
  Session,
  SessionPendingItem,
  SessionStats,
  Stats,
  UsageResponse,
} from "./types.ts";
import { EventBus, sessionIDFromEvent, type EventSink } from "./hub/event-bus.ts";
import {
  agents,
  cancelPendingInput,
  changes,
  children,
  createSession,
  defaultModel,
  devices,
  forkSession,
  forks,
  health,
  messages,
  models,
  pendingInputs,
  projectChanges,
  promptSession,
  session,
  sessionStats,
  stats as readStats,
  switchAgent,
  switchModel,
  trackDevice,
} from "./hub/reads.ts";
import { sleep, syncFast as runFastSync, syncMessagesForChanges as runMessageSync, syncNow as runSyncNow, syncSlow as runSlowSync } from "./hub/sync.ts";
import { CaffeinateSleepGuard, type SleepGuard } from "./hub/sleep.ts";
import { UsageService } from "./hub/usage.ts";

export type { EventSink } from "./hub/event-bus.ts";
export type UsageFetcher = (key: string) => Promise<unknown>;
export type Discovery = () => Promise<OpenCodeLocation | null>;

export interface HubOptions {
  usageFetcher?: UsageFetcher;
  /** Injectable for tests; defaults to the real local-service discovery. */
  discover?: Discovery;
  /** Injectable for tests; defaults to `caffeinate` on macOS. */
  sleepGuard?: SleepGuard;
}

/** Background polling loops that keep the SQLite cache close to OpenCode. */
export class Hub {
  readonly config: HubConfig;
  readonly db: HubDB;
  readonly startedAt = Date.now();

  private readonly bus: EventBus;
  private readonly usage: UsageService;
  private readonly discover: Discovery;
  private readonly sleepGuard: SleepGuard;

  started = false;
  stopped = false;
  client: OpenCodeClient | null = null;
  location: OpenCodeLocation | null = null;
  eventAbort: AbortController | null = null;
  nextDiscoveryAt = 0;
  fastRunning = false;
  fastAgain = false;
  debounce: ReturnType<typeof setTimeout> | null = null;
  lastSessionSignature = "";
  private lastConnectionSignature = "";
  statsInFlight = new Map<string, Promise<Stats | null>>();

  readonly state = {
    connected: false,
    url: null as string | null,
    version: null as string | null,
    lastSync: null as number | null,
    lastError: null as string | null,
  };

  constructor(config: HubConfig, db: HubDB, options: HubOptions = {}) {
    this.config = config;
    this.db = db;
    this.discover = options.discover ?? (() => discoverOpenCode());
    this.sleepGuard =
      options.sleepGuard ?? new CaffeinateSleepGuard((level, message) => this.log(level, message));
    this.bus = new EventBus(config, (level, message) => this.log(level, message), () => this.state.connected);
    this.usage = new UsageService(
      db,
      config,
      options.usageFetcher ?? ((key) => fetchGoUsage(this.config, key)),
      (event) => this.broadcast(event),
      (level, message) => this.log(level, message),
    );
  }

  // MARK: - Lifecycle

  start(): void {
    if (this.started) return;
    this.started = true;
    // Apply the saved sleep preference before polling so a restart does not
    // leave a short window where the Mac can idle-sleep.
    this.sleepGuard.setEnabled(this.config.preventSleep);
    void this.fastLoop();
    void this.slowLoop();
    void this.usageLoop();
  }

  stop(): void {
    this.stopped = true;
    this.eventAbort?.abort();
    this.eventAbort = null;
    if (this.debounce) clearTimeout(this.debounce);
    this.debounce = null;
    this.sleepGuard.stop();
    this.bus.stop();
  }

  private async fastLoop(): Promise<void> {
    while (!this.stopped) {
      await this.syncFast();
      await sleep(this.config.fastPollMs);
    }
  }

  private async slowLoop(): Promise<void> {
    // Give the first fast pull a head start without blocking startup.
    await sleep(1_500);
    while (!this.stopped) {
      await this.syncSlow();
      await sleep(this.config.slowPollMs);
    }
  }

  private async usageLoop(): Promise<void> {
    await sleep(800);
    while (!this.stopped) {
      await this.ensureUsage(false, true).catch(() => null);
      await sleep(this.config.usagePollMs);
    }
  }

  log(level: "debug" | "info" | "warn", message: string): void {
    const order = { debug: 0, info: 1, warn: 2 } as const;
    if (order[level] < order[this.config.logLevel]) return;
    const line = `[hub] ${message}`;
    if (level === "warn") console.error(line);
    else console.log(line);
  }

  // MARK: - Connection

  noteError(error: unknown): void {
    const message = error instanceof Error ? error.message : String(error);
    this.state.lastError = message;
    this.log("warn", message);
  }

  markDisconnected(message: string): void {
    if (this.state.connected) this.log("warn", `OpenCode offline: ${message}`);
    this.state.connected = false;
    this.state.lastError = message;
    this.broadcastConnection();
  }

  /** Drops a stale client so the next loop rediscovers the service. */
  resetConnection(): void {
    this.client = null;
    this.location = null;
    this.eventAbort?.abort();
    this.eventAbort = null;
    this.nextDiscoveryAt = 0;
  }

  async ensureClient(): Promise<OpenCodeClient | null> {
    if (this.client) return this.client;
    const now = Date.now();
    if (now < this.nextDiscoveryAt) return null;
    this.nextDiscoveryAt = now + 10_000;

    const location = await this.discover();
    if (!location) {
      this.markDisconnected("OpenCode service not found");
      return null;
    }

    const changed =
      !this.location ||
      this.location.url !== location.url ||
      this.location.password !== location.password;

    this.location = location;
    this.state.url = location.url;

    if (changed || !this.client) {
      this.client = new OpenCodeClient(location);
      this.state.version = null;
      this.startEventStream();
    }
    return this.client;
  }

  broadcastConnection(): void {
    const signature = `${this.state.connected}|${this.state.url ?? ""}|${this.state.version ?? ""}`;
    if (signature === this.lastConnectionSignature) return;
    this.lastConnectionSignature = signature;
    this.broadcast({
      type: "hub.connection",
      data: {
        connected: this.state.connected,
        url: this.state.url,
        version: this.state.version,
        lastError: this.state.lastError,
      },
    });
  }

  // MARK: - Event stream

  private startEventStream(): void {
    this.eventAbort?.abort();
    const client = this.client;
    if (!client) return;

    const controller = new AbortController();
    this.eventAbort = controller;

    void (async () => {
      let backoff = 1_000;
      while (!this.stopped && !controller.signal.aborted && this.eventAbort === controller) {
        try {
          await client.streamEvents((event) => this.handleEvent(event), controller.signal);
          backoff = 1_000;
        } catch (error) {
          if (controller.signal.aborted) break;
          this.noteError(error);
        }
        if (this.stopped || controller.signal.aborted) break;
        await sleep(backoff);
        backoff = Math.min(backoff * 2, 20_000);
      }
    })();
  }

  private handleEvent(event: HubEvent): void {
    if (event.type === "server.connected") {
      this.state.connected = true;
      this.state.lastError = null;
      this.broadcastConnection();
      this.scheduleFastSync();
    }

    const id = sessionIDFromEvent(event);
    if (id) {
      if (event.type === "session.idle" || event.type === "session.deleted") {
        this.db.markActive(id, false);
      } else if (
        event.type.startsWith("session.step.") ||
        event.type.startsWith("session.text.") ||
        event.type.startsWith("session.reasoning.") ||
        event.type.startsWith("session.tool.") ||
        event.type === "session.created" ||
        event.type === "session.updated" ||
        event.type === "session.usage.updated" ||
        event.type.startsWith("permission.")
      ) {
        this.db.markActive(id, true);
      }

      if (event.type === "session.usage.updated" && event.data) {
        const cost = typeof event.data.cost === "number" ? event.data.cost : undefined;
        const tokens = event.data.tokens;
        this.db.updateSessionUsage(
          id,
          cost,
          tokens && typeof tokens === "object"
            ? (tokens as Parameters<HubDB["updateSessionUsage"]>[2])
            : undefined,
        );
      }
    }

    this.broadcast(event);
    this.scheduleFastSync();
  }

  scheduleFastSync(): void {
    if (this.debounce) return;
    this.debounce = setTimeout(() => {
      this.debounce = null;
      void this.syncFast();
    }, 300);
  }

  // MARK: - Sync delegates

  async syncFast(): Promise<void> {
    return runFastSync(this);
  }

  async syncSlow(): Promise<void> {
    return runSlowSync(this);
  }

  async syncNow(): Promise<void> {
    return runSyncNow(this);
  }

  syncMessagesForChanges(
    client: OpenCodeClient,
    id: string,
    maxPages: number,
    timeoutMs?: number,
  ): Promise<void> {
    return runMessageSync(this, client, id, maxPages, timeoutMs);
  }

  // MARK: - Reads

  trackDevice(device: { id: string; name: string; platform: string; appVersion: string }): void {
    trackDevice(this, device);
  }

  devices(): ConnectedDevice[] {
    return devices(this);
  }

  health(): HubHealth {
    return health(this);
  }

  session(id: string): Promise<Session | null> {
    return session(this, id);
  }

  createSession(input: { title?: string; directory: string }): Promise<Session> {
    return createSession(this, input);
  }

  forkSession(id: string, before?: string | null): Promise<Session> {
    return forkSession(this, id, before);
  }

  forks(id: string): Promise<Session[]> {
    return forks(this, id);
  }

  switchModel(
    id: string,
    model: { id: string; providerID: string; variant?: string },
  ): Promise<void> {
    return switchModel(this, id, model);
  }

  switchAgent(id: string, agent: string): Promise<void> {
    return switchAgent(this, id, agent);
  }

  models(directory?: string): Promise<ModelInfo[]> {
    return models(this, directory);
  }

  defaultModel(directory?: string): Promise<ModelInfo | null> {
    return defaultModel(this, directory);
  }

  agents(directory?: string): Promise<AgentInfo[]> {
    return agents(this, directory);
  }

  promptSession(id: string, text: string, delivery?: "steer" | "queue"): Promise<unknown> {
    return promptSession(this, id, text, delivery);
  }

  pendingInputs(id: string): Promise<SessionPendingItem[]> {
    return pendingInputs(this, id);
  }

  cancelPendingInput(id: string, pendingID: string): Promise<void> {
    return cancelPendingInput(this, id, pendingID);
  }

  children(parentID: string): Promise<Session[]> {
    return children(this, parentID);
  }

  messages(id: string, limit = 100, cursor?: string | null, since?: number): Promise<MessagesResponse> {
    return messages(this, id, limit, cursor, since);
  }

  sessionStats(id: string): Promise<SessionStats | null> {
    return sessionStats(this, id);
  }

  changes(id: string): Promise<FileDiff[]> {
    return changes(this, id);
  }

  projectChanges(projectID: string, sessionLimit = 10): Promise<FileDiff[]> {
    return projectChanges(this, projectID, sessionLimit);
  }

  stats(project?: string): Promise<{ data: Stats; fetchedAt: number; stale: boolean } | null> {
    return readStats(this, project);
  }

  ensureUsage(force = false, awaitFetch = false): Promise<UsageResponse> {
    return this.usage.ensure(force, awaitFetch);
  }

  // MARK: - Event clients

  addClient(sink: EventSink, deviceID?: string): () => void {
    return this.bus.addClient(sink, deviceID);
  }

  activeDeviceIDs(): string[] {
    return this.bus.activeDeviceIDs();
  }

  setEventThrottle(value: number): number {
    return this.bus.setEventThrottle(value);
  }

  /** Applies a new sleep preference immediately. */
  setPreventSleep(enabled: boolean): boolean {
    this.config.preventSleep = enabled;
    this.sleepGuard.setEnabled(enabled);
    return enabled;
  }

  get preventSleepSupported(): boolean {
    return this.sleepGuard.supported;
  }

  broadcast(event: HubEvent): void {
    this.bus.broadcast(event);
  }

  get clientCount(): number {
    return this.bus.clientCount;
  }
}
