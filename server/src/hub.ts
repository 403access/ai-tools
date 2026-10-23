import { clampEventThrottle, HUB_VERSION, type HubConfig } from "./config.ts";
import { DEVICE_STALE_MS, HubDB } from "./db.ts";
import {
  OpenCodeClient,
  OpenCodeError,
  discoverOpenCode,
  fetchGoUsage,
  type OpenCodeLocation,
} from "./opencode.ts";
import type {
  ConnectedDevice,
  FileDiff,
  HubEvent,
  HubHealth,
  MessagesResponse,
  Session,
  SessionPendingItem,
  SessionStats,
  Stats,
  UsageResponse,
} from "./types.ts";

const GLOBAL_STATS_SCOPE = "__global__";
const USAGE_FRESH_MS = 60_000;
const STATS_FRESH_MS = 30_000;
/**
 * Safety valve for the coalescing queue. A burst this large is flushed early
 * instead of growing without bound; coalescing still keeps the common case
 * (streaming deltas) down to a handful of events per window.
 */
const MAX_PENDING_EVENTS = 500;

const DELTA_EVENTS = new Set(["session.text.delta", "session.reasoning.delta"]);

export type EventSink = (event: HubEvent) => void;
export type UsageFetcher = (key: string) => Promise<unknown>;
export type Discovery = () => Promise<OpenCodeLocation | null>;

export interface HubOptions {
  usageFetcher?: UsageFetcher;
  /** Injectable for tests; defaults to the real local-service discovery. */
  discover?: Discovery;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function sessionIDFromEvent(event: HubEvent): string | undefined {
  const data = event.data;
  if (!data) return undefined;
  if (typeof data.sessionID === "string") return data.sessionID;
  const request = data.request;
  if (request && typeof request === "object" && typeof (request as Record<string, unknown>).sessionID === "string") {
    return (request as Record<string, unknown>).sessionID as string;
  }
  return undefined;
}

/**
 * Key used to fold repeated updates while they wait for the next flush. Events
 * without a session (and therefore no natural identity) keep their place in
 * line. Hub notices coalesce by type, which is enough because clients only use
 * them as a "something changed" signal.
 */
function eventCoalesceKey(event: HubEvent): string | null {
  if (event.type.startsWith("hub.")) return event.type;

  const sessionID = sessionIDFromEvent(event);
  if (!sessionID) return null;

  const data = event.data;
  const request = data?.request;
  const requestID =
    request && typeof request === "object" && typeof (request as Record<string, unknown>).id === "string"
      ? ((request as Record<string, unknown>).id as string)
      : "";
  const instance =
    (typeof data?.partID === "string" && data.partID) ||
    (typeof data?.id === "string" && data.id) ||
    (typeof data?.assistantMessageID === "string" && data.assistantMessageID) ||
    (typeof data?.messageID === "string" && data.messageID) ||
    requestID ||
    "";

  return `${event.type}|${sessionID}|${instance}`;
}

/** Folds a streamed delta into the update already waiting for delivery. */
function mergeEvent(previous: HubEvent, next: HubEvent): HubEvent {
  if (!DELTA_EVENTS.has(next.type) || previous.type !== next.type) return next;

  const before = typeof previous.data?.delta === "string" ? previous.data.delta : "";
  if (!before) return next;
  const after = typeof next.data?.delta === "string" ? next.data.delta : "";
  return { ...next, data: { ...(next.data ?? {}), delta: before + after } };
}

export class Hub {
  readonly config: HubConfig;
  readonly db: HubDB;

  /** Event stream sinks with the device id that opened them, when known. */
  private readonly clients = new Map<EventSink, string | undefined>();
  private readonly startedAt = Date.now();
  private readonly fetchUsage: UsageFetcher;
  private readonly discover: Discovery;

  private started = false;
  private stopped = false;
  private client: OpenCodeClient | null = null;
  private location: OpenCodeLocation | null = null;
  private eventAbort: AbortController | null = null;
  private nextDiscoveryAt = 0;
  private fastRunning = false;
  private fastAgain = false;
  private debounce: ReturnType<typeof setTimeout> | null = null;
  /** Updates waiting for the next throttle flush, keyed by their coalesce key. */
  private readonly pending = new Map<string, HubEvent>();
  private pendingSequence = 0;
  private flushTimer: ReturnType<typeof setTimeout> | null = null;
  private usageInFlight: Promise<void> | null = null;
  private statsInFlight = new Map<string, Promise<Stats | null>>();
  private lastSessionSignature = "";
  private lastConnectionSignature = "";

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
    this.fetchUsage = options.usageFetcher ?? ((key) => fetchGoUsage(this.config, key));
    this.discover = options.discover ?? (() => discoverOpenCode());
  }

  // MARK: - Lifecycle

  start(): void {
    if (this.started) return;
    this.started = true;
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
    if (this.flushTimer) clearTimeout(this.flushTimer);
    this.flushTimer = null;
    this.pending.clear();
    this.clients.clear();
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

  private log(level: "debug" | "info" | "warn", message: string): void {
    const order = { debug: 0, info: 1, warn: 2 } as const;
    if (order[level] < order[this.config.logLevel]) return;
    const line = `[hub] ${message}`;
    if (level === "warn") console.error(line);
    else console.log(line);
  }

  // MARK: - Connection

  private noteError(error: unknown): void {
    const message = error instanceof Error ? error.message : String(error);
    this.state.lastError = message;
    this.log("warn", message);
  }

  private markDisconnected(message: string): void {
    if (this.state.connected) this.log("warn", `OpenCode offline: ${message}`);
    this.state.connected = false;
    this.state.lastError = message;
    this.broadcastConnection();
  }

  private async ensureClient(): Promise<OpenCodeClient | null> {
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

  private broadcastConnection(): void {
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

  private scheduleFastSync(): void {
    if (this.debounce) return;
    this.debounce = setTimeout(() => {
      this.debounce = null;
      void this.syncFast();
    }, 300);
  }

  // MARK: - Sync

  async syncFast(): Promise<void> {
    if (this.fastRunning) {
      this.fastAgain = true;
      return;
    }
    this.fastRunning = true;
    try {
      await this.doFastSync();
    } finally {
      this.fastRunning = false;
      if (this.fastAgain && !this.stopped) {
        this.fastAgain = false;
        this.scheduleFastSync();
      }
    }
  }

  private async doFastSync(): Promise<void> {
    const client = await this.ensureClient();
    if (!client) return;

    try {
      const [activeIDs, recent, projects] = await Promise.all([
        client.activeSessionIDs(),
        client.sessions({ limit: 60 }),
        client.projects(),
      ]);

      this.db.upsertSessions(recent);
      const seen = new Set(recent.map((session) => session.id));
      const missing = activeIDs.filter((id) => !seen.has(id));
      if (missing.length) {
        const fetched = await Promise.allSettled(missing.map((id) => client.session(id)));
        const sessions = fetched
          .filter((result): result is PromiseFulfilledResult<Session> => result.status === "fulfilled")
          .map((result) => result.value);
        if (sessions.length) this.db.upsertSessions(sessions);
      }
      this.db.replaceProjects(projects);
      this.db.setActive(new Set(activeIDs));

      this.state.connected = true;
      this.state.url = client.location.url;
      this.state.lastSync = Date.now();
      this.state.lastError = null;

      if (!this.state.version) {
        try {
          const info = await client.serverInfo();
          this.state.version = info.version ?? null;
        } catch {
          // Version is cosmetic; the next cycle can retry.
        }
      }

      const signature = Bun.hash(
        JSON.stringify({
          active: activeIDs.sort(),
          sessions: recent.map((s) => [
            s.id,
            s.time?.updated ?? 0,
            s.cost ?? 0,
            s.tokens?.input ?? 0,
            s.tokens?.output ?? 0,
            s.tokens?.reasoning ?? 0,
          ]),
          projects: projects.map((p) => [p.id, p.time?.updated ?? 0]),
        }),
      ).toString();

      this.broadcastConnection();
      if (signature !== this.lastSessionSignature) {
        this.lastSessionSignature = signature;
        this.broadcast({
          type: "hub.sessions",
          data: { activeCount: activeIDs.length, at: Date.now() },
        });
      }
    } catch (error) {
      this.noteError(error);
      if (error instanceof OpenCodeError && error.unauthorized) {
        this.client = null;
        this.location = null;
        this.eventAbort?.abort();
        this.eventAbort = null;
        this.nextDiscoveryAt = 0;
      }
      this.markDisconnected(error instanceof Error ? error.message : String(error));
    }
  }

  async syncSlow(): Promise<void> {
    const client = await this.ensureClient();
    if (!client) return;

    try {
      const [sessions, stats] = await Promise.all([
        client.sessions({ limit: 1_000 }),
        client.stats(undefined, "detail"),
      ]);
      if (sessions.length) this.db.upsertSessions(sessions);
      if (stats.data) {
        this.db.putStats(GLOBAL_STATS_SCOPE, stats.data);
        this.broadcast({ type: "hub.stats", data: { scope: GLOBAL_STATS_SCOPE, at: Date.now() } });
      }
      this.state.connected = true;
      this.state.lastSync = Date.now();
      this.broadcastConnection();
    } catch (error) {
      this.noteError(error);
    }
  }

  async syncNow(): Promise<void> {
    await Promise.allSettled([
      this.syncFast(),
      this.syncSlow(),
      this.ensureUsage(true, true),
    ]);
  }

  // MARK: - Devices

  /** Remembers a client app that made a request to the hub. */
  trackDevice(device: {
    id: string;
    name: string;
    platform: string;
    appVersion: string;
  }): void {
    this.db.upsertDevice(device);
  }

  /**
   * Devices that have contacted the hub, with a live flag for those that still
   * have an event stream open or have polled in the last few seconds.
   */
  devices(): ConnectedDevice[] {
    const streaming = new Set(
      [...this.clients.values()].filter((id): id is string => Boolean(id)),
    );
    const recentCutoff = Date.now() - DEVICE_STALE_MS;
    return this.db.getDevices().map((device) => ({
      ...device,
      connected: streaming.has(device.id) || device.lastSeen >= recentCutoff,
    }));
  }

  // MARK: - Reads

  health(): HubHealth {
    const counts = this.db.counts();
    return {
      version: HUB_VERSION,
      uptime: Math.round((Date.now() - this.startedAt) / 1000),
      db: this.db.path,
      sessions: counts.sessions,
      messages: counts.messages,
      projects: counts.projects,
      opencode: {
        connected: this.state.connected,
        url: this.state.url,
        version: this.state.version,
        lastSync: this.state.lastSync,
        lastError: this.state.lastError,
      },
    };
  }

  async session(id: string): Promise<Session | null> {
    const client = this.client ?? (await this.ensureClient());
    if (client) {
      try {
        const session = await client.session(id);
        this.db.upsertSessions([session]);
        return session;
      } catch (error) {
        this.noteError(error);
      }
    }
    return this.db.getSession(id);
  }

  /** Starts a new OpenCode session in a project directory. */
  async createSession(input: { title?: string; directory: string }): Promise<Session> {
    const client = this.client ?? (await this.ensureClient());
    if (!client) throw new OpenCodeError("OpenCode is offline", 503);

    const session = await client.createSession(input);
    this.db.upsertSessions([session]);
    this.broadcast({ type: "hub.sessions", data: { at: Date.now() } });
    return session;
  }

  /**
   * Sends a prompt into an existing session. The service admits the message
   * durably and schedules the agent loop, so the session is marked running
   * immediately rather than waiting for the next poll.
   */
  async promptSession(
    id: string,
    text: string,
    delivery?: "steer" | "queue",
  ): Promise<unknown> {
    const client = this.client ?? (await this.ensureClient());
    if (!client) throw new OpenCodeError("OpenCode is offline", 503);

    const result = await client.promptSession(id, text, delivery);
    this.db.markActive(id, true);
    this.broadcast({ type: "hub.sessions", data: { at: Date.now() } });
    return result;
  }

  /**
   * Inputs the service has admitted but not delivered yet. There is no cached
   * copy: the queue only exists while the service is reachable.
   */
  async pendingInputs(id: string): Promise<SessionPendingItem[]> {
    const client = this.client ?? (await this.ensureClient());
    if (!client) return [];
    try {
      return await client.pending(id);
    } catch (error) {
      this.noteError(error);
      return [];
    }
  }

  /** Cancels one queued input that has not started yet. */
  async cancelPendingInput(id: string, pendingID: string): Promise<void> {
    const client = this.client ?? (await this.ensureClient());
    if (!client) throw new OpenCodeError("OpenCode is offline", 503);
    await client.cancelPending(id, pendingID);
  }

  async children(parentID: string): Promise<Session[]> {
    const cached = this.db.getSessions({ parentID, limit: 50 });
    const client = this.client ?? (await this.ensureClient());
    if (!client) return cached;
    try {
      const children = await client.sessions({ parentID, limit: 50 });
      if (children.length) this.db.upsertSessions(children);
      return children;
    } catch (error) {
      this.noteError(error);
      return cached;
    }
  }

  async messages(
    id: string,
    limit = 100,
    cursor?: string | null,
    since?: number,
  ): Promise<MessagesResponse> {
    const client = this.client ?? (await this.ensureClient());
    if (client) {
      try {
        if (since !== undefined) {
          // Refresh the newest window so in-place streaming updates are cached,
          // then answer from the cache with only the messages the client lacks.
          const page = await client.messages(id, Math.max(limit, 100));
          if (page.data?.length) this.db.upsertMessages(id, page.data);
          return { data: this.db.getMessagesSince(id, since) };
        }
        const response = await client.messages(id, limit, cursor);
        if (response.data?.length) this.db.upsertMessages(id, response.data);
        return response;
      } catch (error) {
        this.noteError(error);
        if (since !== undefined) return { data: this.db.getMessagesSince(id, since) };
        const cached = this.db.getMessages(id, limit, cursor);
        if (cached.data.length || this.db.getMessageCount(id) === 0) return cached;
        throw error;
      }
    }
    if (since !== undefined) return { data: this.db.getMessagesSince(id, since) };
    return this.db.getMessages(id, limit, cursor);
  }

  /**
   * Per-session stats. Message history is the source of truth, so the first
   * request hydrates it (bounded) before aggregating the cached tool calls.
   */
  async sessionStats(id: string): Promise<SessionStats | null> {
    const client = this.client ?? (await this.ensureClient());
    if (client) {
      try {
        const session = await client.session(id);
        this.db.upsertSessions([session]);
      } catch (error) {
        this.noteError(error);
      }
      try {
        await this.syncMessagesForChanges(client, id, 30, 8_000);
      } catch (error) {
        this.noteError(error);
      }
    }
    return this.db.getSessionStats(id);
  }

  /**
   * File changes recorded by a session's edit/write tool calls. Message history
   * is the source of truth: the first request hydrates and caches it, later
   * requests only pull the newest page while the session keeps moving.
   */
  async changes(id: string): Promise<FileDiff[]> {
    const client = this.client ?? (await this.ensureClient());
    if (client) {
      try {
        await this.syncMessagesForChanges(client, id, 25);
      } catch (error) {
        this.noteError(error);
      }
    }
    return this.db.getChanges(id);
  }

  /**
   * Changes across the newest sessions in a project. Hydration is bounded so a
   * project with a long history still answers quickly; cached changes from
   * older sessions are always included.
   */
  async projectChanges(projectID: string, sessionLimit = 10): Promise<FileDiff[]> {
    const client = this.client ?? (await this.ensureClient());
    if (client) {
      const sessions = this.db.getSessions({ project: projectID, limit: sessionLimit });
      // Two at a time, a few pages each, with a short per-request timeout. The
      // local OpenCode service serializes message reads, so being greedy here
      // makes the whole history endpoint time out.
      for (let index = 0; index < sessions.length; index += 2) {
        const batch = sessions.slice(index, index + 2);
        await Promise.allSettled(
          batch.map((session) => this.syncMessagesForChanges(client, session.id, 4, 6_000)),
        );
      }
    }
    return this.db.getProjectChanges(projectID);
  }

  /**
   * Pages a session's messages into SQLite, newest first. A completed sync only
   * refreshes the first page; an incomplete one continues from the oldest
   * cursor it reached last time.
   */
  private async syncMessagesForChanges(
    client: OpenCodeClient,
    id: string,
    maxPages: number,
    timeoutMs?: number,
  ): Promise<void> {
    const sync = this.db.getMessageSync(id);
    const session = this.db.getSession(id);
    const now = Date.now();

    if (sync && now - sync.syncedAt < 10_000) return;
    if (sync?.complete && session && session.time.updated <= sync.syncedAt) return;

    let oldest = sync?.oldestCursor ?? null;
    let complete = sync?.complete ?? false;

    try {
      // Refresh the newest page whenever the session has moved (or first seen).
      if (!sync || !session || session.time.updated > sync.syncedAt) {
        const page = await client.messages(id, 100, undefined, timeoutMs);
        if (page.data.length) this.db.upsertMessages(id, page.data);
        if (!sync) {
          oldest = page.cursor?.previous ?? null;
          complete = oldest === null;
        }
      }

      let pages = 0;
      while (!complete && oldest && pages < maxPages) {
        const page = await client.messages(id, 100, oldest, timeoutMs);
        if (page.data.length) this.db.upsertMessages(id, page.data);
        const next = page.cursor?.previous ?? null;
        if (!next) complete = true;
        else oldest = next;
        pages += 1;
      }
    } catch (error) {
      // Keep whatever was cached and do not retry this session on every poll.
      this.noteError(error);
      this.db.putMessageSync(id, {
        syncedAt: Date.now(),
        oldestCursor: complete ? null : oldest,
        complete,
      });
      return;
    }

    this.db.putMessageSync(id, {
      syncedAt: Date.now(),
      oldestCursor: complete ? null : oldest,
      complete,
    });
  }

  async stats(project?: string): Promise<{ data: Stats; fetchedAt: number; stale: boolean } | null> {
    const scope = project ?? GLOBAL_STATS_SCOPE;
    const cached = this.db.getStats(scope);
    if (cached && Date.now() - cached.fetchedAt < STATS_FRESH_MS) {
      return { ...cached, stale: false };
    }

    const inFlight = this.statsInFlight.get(scope);
    if (inFlight) {
      const data = await inFlight;
      return data ? { data, fetchedAt: Date.now(), stale: false } : cached ? { ...cached, stale: true } : null;
    }

    const client = this.client ?? (await this.ensureClient());
    if (!client) return cached ? { ...cached, stale: true } : null;

    const task = (async (): Promise<Stats | null> => {
      try {
        const response = await client.stats(project, "detail");
        if (!response.data) return null;
        this.db.putStats(scope, response.data);
        this.broadcast({ type: "hub.stats", data: { scope, at: Date.now() } });
        return response.data;
      } catch (error) {
        this.noteError(error);
        return null;
      } finally {
        this.statsInFlight.delete(scope);
      }
    })();

    this.statsInFlight.set(scope, task);
    const data = await task;
    if (data) return { data, fetchedAt: Date.now(), stale: false };
    return cached ? { ...cached, stale: true } : null;
  }

  async ensureUsage(force = false, awaitFetch = false): Promise<UsageResponse> {
    const cached = this.db.getUsage();
    const configured = Boolean(this.config.goUsageKey);

    if (!configured) {
      return { data: null, fetchedAt: null, stale: false, error: null, configured: false };
    }

    const fresh = cached.fetchedAt !== null && Date.now() - cached.fetchedAt < USAGE_FRESH_MS;
    if (!force && fresh) return this.usageResponse(cached, false);

    if (!this.usageInFlight) {
      this.usageInFlight = this.refreshUsage().finally(() => {
        this.usageInFlight = null;
      });
    }

    if (!awaitFetch && cached.data) {
      void this.usageInFlight;
      return this.usageResponse(cached, true);
    }

    await this.usageInFlight;
    const updated = this.db.getUsage();
    return this.usageResponse(updated, false);
  }

  private async refreshUsage(): Promise<void> {
    const key = this.config.goUsageKey;
    if (!key) return;
    try {
      const usage = (await this.fetchUsage(key)) as Parameters<HubDB["putUsage"]>[0];
      this.db.putUsage(usage, Date.now(), null);
      this.broadcast({ type: "hub.usage", data: { at: Date.now() } });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      this.db.putUsageError(message);
      this.log("warn", `usage: ${message}`);
      this.broadcast({ type: "hub.usage", data: { at: Date.now(), error: message } });
    }
  }

  private usageResponse(
    cached: ReturnType<HubDB["getUsage"]>,
    staleWhileRefreshing: boolean,
  ): UsageResponse {
    const stale =
      staleWhileRefreshing ||
      cached.error !== null ||
      cached.fetchedAt === null ||
      Date.now() - cached.fetchedAt > USAGE_FRESH_MS * 5;
    return {
      data: cached.data,
      fetchedAt: cached.fetchedAt,
      stale,
      error: cached.error,
      configured: true,
    };
  }

  // MARK: - Event clients

  addClient(sink: EventSink, deviceID?: string): () => void {
    this.clients.set(sink, deviceID);
    sink({
      type: "hub.connected",
      data: {
        version: HUB_VERSION,
        opencode: this.state.connected,
        at: Date.now(),
      },
    });
    return () => this.clients.delete(sink);
  }

  /**
   * Changes the coalescing window for updates sent to the apps. The value is
   * clamped and takes effect immediately; queued updates follow the new window.
   */
  setEventThrottle(value: number): number {
    const ms = clampEventThrottle(value);
    this.config.eventThrottleMs = ms;

    if (ms === 0) {
      this.flushPending();
    } else if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
      this.scheduleFlush();
    }

    this.log("info", `Event throttle set to ${ms}ms`);
    return ms;
  }

  /**
   * Fans an event out to the connected apps. When throttling is enabled the
   * event is folded into a pending batch, so a busy session produces one update
   * per window instead of one per token.
   */
  broadcast(event: HubEvent): void {
    // Nobody is listening: the next client seeds itself from the cache.
    if (this.clients.size === 0) return;

    if (this.config.eventThrottleMs <= 0) {
      this.deliver(event);
      return;
    }

    const key = eventCoalesceKey(event) ?? `#${this.pendingSequence++}`;
    const previous = this.pending.get(key);
    this.pending.set(key, previous ? mergeEvent(previous, event) : event);

    if (this.pending.size >= MAX_PENDING_EVENTS) {
      this.flushPending();
      return;
    }
    this.scheduleFlush();
  }

  private scheduleFlush(): void {
    if (this.flushTimer) return;
    this.flushTimer = setTimeout(() => {
      this.flushTimer = null;
      this.flushPending();
    }, this.config.eventThrottleMs);
  }

  private flushPending(): void {
    if (this.flushTimer) {
      clearTimeout(this.flushTimer);
      this.flushTimer = null;
    }
    if (this.pending.size === 0) return;

    const events = [...this.pending.values()];
    this.pending.clear();
    for (const event of events) this.deliver(event);
  }

  private deliver(event: HubEvent): void {
    for (const sink of this.clients.keys()) {
      try {
        sink(event);
      } catch {
        this.clients.delete(sink);
      }
    }
  }
}
