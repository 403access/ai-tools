import type { HubConfig } from "../config.ts";
import type { HubDB } from "../db.ts";
import type { HubEvent, UsageResponse } from "../types.ts";
import type { UsageFetcher } from "../hub.ts";

const USAGE_FRESH_MS = 60_000;

/** Caches Go plan quota and coalesces concurrent refreshes. */
export class UsageService {
  private inFlight: Promise<void> | null = null;

  constructor(
    private readonly db: HubDB,
    private readonly config: HubConfig,
    private readonly fetchUsage: UsageFetcher,
    private readonly broadcast: (event: HubEvent) => void,
    private readonly log: (level: "debug" | "info" | "warn", message: string) => void,
  ) {}

  async ensure(force = false, awaitFetch = false): Promise<UsageResponse> {
    const cached = this.db.getUsage();
    const configured = Boolean(this.config.goUsageKey);

    if (!configured) {
      return { data: null, fetchedAt: null, stale: false, error: null, configured: false };
    }

    const fresh = cached.fetchedAt !== null && Date.now() - cached.fetchedAt < USAGE_FRESH_MS;
    if (!force && fresh) return this.response(cached, false);

    if (!this.inFlight) {
      this.inFlight = this.refresh().finally(() => {
        this.inFlight = null;
      });
    }

    if (!awaitFetch && cached.data) {
      void this.inFlight;
      return this.response(cached, true);
    }

    await this.inFlight;
    const updated = this.db.getUsage();
    return this.response(updated, false);
  }

  private async refresh(): Promise<void> {
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

  private response(
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
}
