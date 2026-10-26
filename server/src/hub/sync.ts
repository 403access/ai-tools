import { OpenCodeError } from "../opencode.ts";
import type { Session } from "../types.ts";
import type { Hub } from "../hub.ts";
import { GLOBAL_STATS_SCOPE } from "./constants.ts";

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function syncFast(hub: Hub): Promise<void> {
  if (hub.fastRunning) {
    hub.fastAgain = true;
    return;
  }
  hub.fastRunning = true;
  try {
    await doFastSync(hub);
  } finally {
    hub.fastRunning = false;
    if (hub.fastAgain && !hub.stopped) {
      hub.fastAgain = false;
      hub.scheduleFastSync();
    }
  }
}

async function doFastSync(hub: Hub): Promise<void> {
  const client = await hub.ensureClient();
  if (!client) return;

  try {
    const [activeIDs, recent, projects] = await Promise.all([
      client.activeSessionIDs(),
      client.sessions({ limit: 60 }),
      client.projects(),
    ]);

    hub.db.upsertSessions(recent);
    const seen = new Set(recent.map((session) => session.id));
    const missing = activeIDs.filter((id) => !seen.has(id));
    if (missing.length) {
      const fetched = await Promise.allSettled(missing.map((id) => client.session(id)));
      const sessions = fetched
        .filter((result): result is PromiseFulfilledResult<Session> => result.status === "fulfilled")
        .map((result) => result.value);
      if (sessions.length) hub.db.upsertSessions(sessions);
    }
    hub.db.replaceProjects(projects);
    hub.db.setActive(new Set(activeIDs));

    hub.state.connected = true;
    hub.state.url = client.location.url;
    hub.state.lastSync = Date.now();
    hub.state.lastError = null;

    if (!hub.state.version) {
      try {
        const info = await client.serverInfo();
        hub.state.version = info.version ?? null;
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
          s.fork?.sessionID ?? null,
        ]),
        projects: projects.map((p) => [p.id, p.time?.updated ?? 0]),
      }),
    ).toString();

    hub.broadcastConnection();
    if (signature !== hub.lastSessionSignature) {
      hub.lastSessionSignature = signature;
      hub.broadcast({
        type: "hub.sessions",
        data: { activeCount: activeIDs.length, at: Date.now() },
      });
    }
  } catch (error) {
    hub.noteError(error);
    if (error instanceof OpenCodeError && error.unauthorized) {
      hub.resetConnection();
    }
    hub.markDisconnected(error instanceof Error ? error.message : String(error));
  }
}

export async function syncSlow(hub: Hub): Promise<void> {
  const client = await hub.ensureClient();
  if (!client) return;

  try {
    const [sessions, stats] = await Promise.all([
      client.sessions({ limit: 1_000 }),
      client.stats(undefined, "detail"),
    ]);
    if (sessions.length) hub.db.upsertSessions(sessions);
    if (stats.data) {
      hub.db.putStats(GLOBAL_STATS_SCOPE, stats.data);
      hub.broadcast({ type: "hub.stats", data: { scope: GLOBAL_STATS_SCOPE, at: Date.now() } });
    }
    hub.state.connected = true;
    hub.state.lastSync = Date.now();
    hub.broadcastConnection();
  } catch (error) {
    hub.noteError(error);
  }
}

export async function syncNow(hub: Hub): Promise<void> {
  await Promise.allSettled([
    syncFast(hub),
    syncSlow(hub),
    hub.ensureUsage(true, true),
  ]);
}

/** Waits between background loop iterations. */
export { sleep };

/**
 * Pages a session's messages into SQLite, newest first. A completed sync only
 * refreshes the first page; an incomplete one continues from the oldest
 * cursor it reached last time.
 */
export async function syncMessagesForChanges(
  hub: Hub,
  client: NonNullable<Hub["client"]>,
  id: string,
  maxPages: number,
  timeoutMs?: number,
): Promise<void> {
  const sync = hub.db.getMessageSync(id);
  const session = hub.db.getSession(id);
  const now = Date.now();

  if (sync && now - sync.syncedAt < 10_000) return;
  if (sync?.complete && session && session.time.updated <= sync.syncedAt) return;

  let oldest = sync?.oldestCursor ?? null;
  let complete = sync?.complete ?? false;

  try {
    // Refresh the newest page whenever the session has moved (or first seen).
    if (!sync || !session || session.time.updated > sync.syncedAt) {
      const page = await client.messages(id, 100, undefined, timeoutMs);
      if (page.data.length) hub.db.upsertMessages(id, page.data);
      if (!sync) {
        oldest = page.cursor?.previous ?? null;
        complete = oldest === null;
      }
    }

    let pages = 0;
    while (!complete && oldest && pages < maxPages) {
      const page = await client.messages(id, 100, oldest, timeoutMs);
      if (page.data.length) hub.db.upsertMessages(id, page.data);
      const next = page.cursor?.previous ?? null;
      if (!next) complete = true;
      else oldest = next;
      pages += 1;
    }
  } catch (error) {
    // Keep whatever was cached and do not retry this session on every poll.
    hub.noteError(error);
    hub.db.putMessageSync(id, {
      syncedAt: Date.now(),
      oldestCursor: complete ? null : oldest,
      complete,
    });
    return;
  }

  hub.db.putMessageSync(id, {
    syncedAt: Date.now(),
    oldestCursor: complete ? null : oldest,
    complete,
  });
}
