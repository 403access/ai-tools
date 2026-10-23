import { clampEventThrottle, HUB_VERSION, type HubConfig } from "../config.ts";
import type { HubEvent } from "../types.ts";

export type EventSink = (event: HubEvent) => void;

/**
 * Safety valve for the coalescing queue. A burst this large is flushed early
 * instead of growing without bound; coalescing still keeps the common case
 * (streaming deltas) down to a handful of events per window.
 */
const MAX_PENDING_EVENTS = 500;

const DELTA_EVENTS = new Set(["session.text.delta", "session.reasoning.delta"]);

export function sessionIDFromEvent(event: HubEvent): string | undefined {
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

/**
 * Fan-out for connected apps. Throttled broadcasts are coalesced by session
 * (and streamed deltas by part) so a busy session produces one update per
 * window instead of one per token.
 */
export class EventBus {
  /** Event stream sinks with the device id that opened them, when known. */
  private readonly clients = new Map<EventSink, string | undefined>();
  private readonly pending = new Map<string, HubEvent>();
  private pendingSequence = 0;
  private flushTimer: ReturnType<typeof setTimeout> | null = null;

  constructor(
    private readonly config: HubConfig,
    private readonly log: (level: "debug" | "info" | "warn", message: string) => void,
    private readonly isOpenCodeConnected: () => boolean,
  ) {}

  get clientCount(): number {
    return this.clients.size;
  }

  activeDeviceIDs(): string[] {
    return [...this.clients.values()].filter((id): id is string => Boolean(id));
  }

  addClient(sink: EventSink, deviceID?: string): () => void {
    this.clients.set(sink, deviceID);
    sink({
      type: "hub.connected",
      data: {
        version: HUB_VERSION,
        opencode: this.isOpenCodeConnected(),
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

  stop(): void {
    if (this.flushTimer) clearTimeout(this.flushTimer);
    this.flushTimer = null;
    this.pending.clear();
    this.clients.clear();
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
