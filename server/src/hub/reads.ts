import { HUB_VERSION } from "../config.ts";
import { DEVICE_STALE_MS } from "../db.ts";
import { OpenCodeError } from "../opencode.ts";
import type {
  AgentInfo,
  ConnectedDevice,
  FileDiff,
  HubHealth,
  MessagesResponse,
  ModelInfo,
  Session,
  SessionPendingItem,
  SessionStats,
  Stats,
} from "../types.ts";
import type { Hub } from "../hub.ts";
import { GLOBAL_STATS_SCOPE, STATS_FRESH_MS } from "./constants.ts";
import { syncMessagesForChanges } from "./sync.ts";

export function health(hub: Hub): HubHealth {
  const counts = hub.db.counts();
  return {
    version: HUB_VERSION,
    uptime: Math.round((Date.now() - hub.startedAt) / 1000),
    db: hub.db.path,
    sessions: counts.sessions,
    messages: counts.messages,
    projects: counts.projects,
    opencode: {
      connected: hub.state.connected,
      url: hub.state.url,
      version: hub.state.version,
      lastSync: hub.state.lastSync,
      lastError: hub.state.lastError,
    },
  };
}

/** Remembers a client app that made a request to the hub. */
export function trackDevice(
  hub: Hub,
  device: { id: string; name: string; platform: string; appVersion: string },
): void {
  hub.db.upsertDevice(device);
}

/**
 * Devices that have contacted the hub, with a live flag for those that still
 * have an event stream open or have polled in the last few seconds.
 */
export function devices(hub: Hub): ConnectedDevice[] {
  const streaming = new Set(hub.activeDeviceIDs());
  const recentCutoff = Date.now() - DEVICE_STALE_MS;
  return hub.db.getDevices().map((device) => ({
    ...device,
    connected: streaming.has(device.id) || device.lastSeen >= recentCutoff,
  }));
}

export async function session(hub: Hub, id: string): Promise<Session | null> {
  const client = hub.client ?? (await hub.ensureClient());
  if (client) {
    try {
      const fresh = await client.session(id);
      hub.db.upsertSessions([fresh]);
      return fresh;
    } catch (error) {
      hub.noteError(error);
    }
  }
  return hub.db.getSession(id);
}

/** Starts a new OpenCode session in a project directory. */
export async function createSession(hub: Hub, input: { title?: string; directory: string }): Promise<Session> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);

  const created = await client.createSession(input);
  hub.db.upsertSessions([created]);
  hub.broadcast({ type: "hub.sessions", data: { at: Date.now() } });
  return created;
}

/** Copies a session's history into a new child session. */
export async function forkSession(
  hub: Hub,
  id: string,
  before?: string | null,
): Promise<Session> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);

  const forked = await client.forkSession(id, before);
  hub.db.upsertSessions([forked]);
  hub.broadcast({ type: "hub.sessions", data: { at: Date.now() } });
  return forked;
}

/** Switches the model used by later turns, then refreshes the cached row. */
export async function switchModel(
  hub: Hub,
  id: string,
  model: { id: string; providerID: string; variant?: string },
): Promise<void> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);

  await client.switchModel(id, model);
  await refreshSession(hub, client, id);
  hub.broadcast({ type: "hub.sessions", data: { id, at: Date.now() } });
}

/** Switches the agent used by later turns, then refreshes the cached row. */
export async function switchAgent(hub: Hub, id: string, agent: string): Promise<void> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);

  await client.switchAgent(id, agent);
  await refreshSession(hub, client, id);
  hub.broadcast({ type: "hub.sessions", data: { id, at: Date.now() } });
}

async function refreshSession(hub: Hub, client: NonNullable<Hub["client"]>, id: string): Promise<void> {
  try {
    const fresh = await client.session(id);
    hub.db.upsertSessions([fresh]);
  } catch (error) {
    // The switch already succeeded; a stale cached row is harmless.
    hub.noteError(error);
  }
}

/** Models available for a directory. */
export async function models(hub: Hub, directory?: string): Promise<ModelInfo[]> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);
  return client.models(directory);
}

/** Agents available for a directory. */
export async function agents(hub: Hub, directory?: string): Promise<AgentInfo[]> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);
  return client.agents(directory);
}

/** Model OpenCode uses when a session has no explicit selection. */
export async function defaultModel(hub: Hub, directory?: string): Promise<ModelInfo | null> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);
  return client.defaultModel(directory);
}

/**
 * Sends a prompt into an existing session. The service admits the message
 * durably and schedules the agent loop, so the session is marked running
 * immediately rather than waiting for the next poll.
 */
export async function promptSession(
  hub: Hub,
  id: string,
  text: string,
  delivery?: "steer" | "queue",
): Promise<unknown> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);

  const result = await client.promptSession(id, text, delivery);
  hub.db.markActive(id, true);
  hub.broadcast({ type: "hub.sessions", data: { at: Date.now() } });
  return result;
}

/**
 * Inputs the service has admitted but not delivered yet. There is no cached
 * copy: the queue only exists while the service is reachable.
 */
export async function pendingInputs(hub: Hub, id: string): Promise<SessionPendingItem[]> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) return [];
  try {
    return await client.pending(id);
  } catch (error) {
    hub.noteError(error);
    return [];
  }
}

/** Cancels one queued input that has not started yet. */
export async function cancelPendingInput(hub: Hub, id: string, pendingID: string): Promise<void> {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);
  await client.cancelPending(id, pendingID);
}

export async function children(hub: Hub, parentID: string): Promise<Session[]> {
  const cached = hub.db.getSessions({ parentID, limit: 50 });
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) return cached;
  try {
    const list = await client.sessions({ parentID, limit: 50 });
    if (list.length) hub.db.upsertSessions(list);
    return list;
  } catch (error) {
    hub.noteError(error);
    return cached;
  }
}

export async function messages(
  hub: Hub,
  id: string,
  limit = 100,
  cursor?: string | null,
  since?: number,
): Promise<MessagesResponse> {
  const client = hub.client ?? (await hub.ensureClient());
  if (client) {
    try {
      if (since !== undefined) {
        // Refresh the newest window so in-place streaming updates are cached,
        // then answer from the cache with only the messages the client lacks.
        const page = await client.messages(id, Math.max(limit, 100));
        if (page.data?.length) hub.db.upsertMessages(id, page.data);
        return { data: hub.db.getMessagesSince(id, since) };
      }
      const response = await client.messages(id, limit, cursor);
      if (response.data?.length) hub.db.upsertMessages(id, response.data);
      return response;
    } catch (error) {
      hub.noteError(error);
      if (since !== undefined) return { data: hub.db.getMessagesSince(id, since) };
      const cached = hub.db.getMessages(id, limit, cursor);
      if (cached.data.length || hub.db.getMessageCount(id) === 0) return cached;
      throw error;
    }
  }
  if (since !== undefined) return { data: hub.db.getMessagesSince(id, since) };
  return hub.db.getMessages(id, limit, cursor);
}

/**
 * Per-session stats. Message history is the source of truth, so the first
 * request hydrates it (bounded) before aggregating the cached tool calls.
 */
export async function sessionStats(hub: Hub, id: string): Promise<SessionStats | null> {
  const client = hub.client ?? (await hub.ensureClient());
  if (client) {
    try {
      const fresh = await client.session(id);
      hub.db.upsertSessions([fresh]);
    } catch (error) {
      hub.noteError(error);
    }
    try {
      await syncMessagesForChanges(hub, client, id, 30, 8_000);
    } catch (error) {
      hub.noteError(error);
    }
  }
  return hub.db.getSessionStats(id);
}

/**
 * File changes recorded by a session's edit/write tool calls. Message history
 * is the source of truth: the first request hydrates and caches it, later
 * requests only pull the newest page while the session keeps moving.
 */
export async function changes(hub: Hub, id: string): Promise<FileDiff[]> {
  const client = hub.client ?? (await hub.ensureClient());
  if (client) {
    try {
      await syncMessagesForChanges(hub, client, id, 25);
    } catch (error) {
      hub.noteError(error);
    }
  }
  return hub.db.getChanges(id);
}

/**
 * Changes across the newest sessions in a project. Hydration is bounded so a
 * project with a long history still answers quickly; cached changes from
 * older sessions are always included.
 */
export async function projectChanges(hub: Hub, projectID: string, sessionLimit = 10): Promise<FileDiff[]> {
  const client = hub.client ?? (await hub.ensureClient());
  if (client) {
    const sessions = hub.db.getSessions({ project: projectID, limit: sessionLimit });
    // Two at a time, a few pages each, with a short per-request timeout. The
    // local OpenCode service serializes message reads, so being greedy here
    // makes the whole history endpoint time out.
    for (let index = 0; index < sessions.length; index += 2) {
      const batch = sessions.slice(index, index + 2);
      await Promise.allSettled(
        batch.map((item) => syncMessagesForChanges(hub, client, item.id, 4, 6_000)),
      );
    }
  }
  return hub.db.getProjectChanges(projectID);
}

export async function stats(
  hub: Hub,
  project?: string,
): Promise<{ data: Stats; fetchedAt: number; stale: boolean } | null> {
  const scope = project ?? GLOBAL_STATS_SCOPE;
  const cached = hub.db.getStats(scope);
  if (cached && Date.now() - cached.fetchedAt < STATS_FRESH_MS) {
    return { ...cached, stale: false };
  }

  const inFlight = hub.statsInFlight.get(scope);
  if (inFlight) {
    const data = await inFlight;
    return data ? { data, fetchedAt: Date.now(), stale: false } : cached ? { ...cached, stale: true } : null;
  }

  const client = hub.client ?? (await hub.ensureClient());
  if (!client) return cached ? { ...cached, stale: true } : null;

  const task = (async (): Promise<Stats | null> => {
    try {
      const response = await client.stats(project, "detail");
      if (!response.data) return null;
      hub.db.putStats(scope, response.data);
      hub.broadcast({ type: "hub.stats", data: { scope, at: Date.now() } });
      return response.data;
    } catch (error) {
      hub.noteError(error);
      return null;
    } finally {
      hub.statsInFlight.delete(scope);
    }
  })();

  hub.statsInFlight.set(scope, task);
  const data = await task;
  if (data) return { data, fetchedAt: Date.now(), stale: false };
  return cached ? { ...cached, stale: true } : null;
}
