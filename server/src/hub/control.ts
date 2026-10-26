import { OpenCodeError } from "../opencode.ts";
import type { Hub } from "../hub.ts";
import type { Session } from "../types.ts";

/** Text sent when the user (or a timer) continues a held session. */
export const CONTINUE_PROMPT = "continue";

/** Longest timed pause or queue delay accepted by the hub. */
export const MAX_PAUSE_MS = 30 * 24 * 60 * 60 * 1000;
export const MAX_QUEUE_MS = MAX_PAUSE_MS;

async function requireClient(hub: Hub) {
  const client = hub.client ?? (await hub.ensureClient());
  if (!client) throw new OpenCodeError("OpenCode is offline", 503);
  return client;
}

/**
 * Makes sure the session exists in the cache before a control update. A control
 * change is logged to the sync feed, so the row must be present for clients to
 * receive it.
 */
async function requireSession(
  hub: Hub,
  client: NonNullable<Hub["client"]>,
  id: string,
): Promise<Session> {
  const cached = hub.db.getSession(id);
  if (cached) return cached;

  const fresh = await client.session(id);
  hub.db.upsertSessions([fresh]);
  const stored = hub.db.getSession(id);
  if (!stored) throw new OpenCodeError("Session not found", 404);
  return stored;
}

function broadcastSession(hub: Hub, id: string): void {
  hub.broadcast({ type: "hub.sessions", data: { id, at: Date.now() } });
}

/**
 * Interrupts the current turn and holds the session until `until`. OpenCode
 * cannot schedule its own continuation, so the hub keeps the deadline and
 * sends a prompt when it expires (including after a hub restart).
 */
export async function pauseSession(
  hub: Hub,
  id: string,
  until: number,
): Promise<Session> {
  const client = await requireClient(hub);
  await requireSession(hub, client, id);

  await client.interruptSession(id, false);
  if (!hub.db.setSessionPause(id, until)) {
    throw new OpenCodeError("Session not found", 404);
  }
  broadcastSession(hub, id);
  return hub.db.getSession(id)!;
}

/** Interrupts the current turn and holds the session until the user continues. */
export async function stopSession(hub: Hub, id: string): Promise<Session> {
  const client = await requireClient(hub);
  await requireSession(hub, client, id);

  await client.interruptSession(id, false);
  if (!hub.db.setSessionStop(id)) {
    throw new OpenCodeError("Session not found", 404);
  }
  broadcastSession(hub, id);
  return hub.db.getSession(id)!;
}

/**
 * Clears a pause or stop and sends `continue` into the conversation. Sending a
 * prompt is what restarts the agent loop after an interrupt; OpenCode does not
 * expose a "resume the interrupted turn" operation.
 */
export async function continueSession(hub: Hub, id: string): Promise<Session> {
  const client = await requireClient(hub);
  await requireSession(hub, client, id);

  // A pause can expire while every concurrency slot is busy. Hold the
  // continuation on the board instead of exceeding the limit.
  if (shouldQueuePrompt(hub, id)) {
    return queueSession(hub, id, CONTINUE_PROMPT);
  }

  await client.promptSession(id, CONTINUE_PROMPT);
  hub.db.clearSessionControl(id);
  hub.db.markActive(id, true, Date.now());
  hub.db.recordTaskPrompt(id, CONTINUE_PROMPT);
  broadcastSession(hub, id);
  return hub.db.getSession(id)!;
}

/** True when a prompt should wait instead of starting a new agent turn. */
export function shouldQueuePrompt(hub: Hub, id: string, startAt?: number): boolean {
  // A running turn already owns a slot; never park its next prompt mid-flight.
  if (hub.db.isSessionActive(id)) return false;
  if (startAt !== undefined && startAt > Date.now()) return true;
  const limit = hub.config.maxConcurrentAgents;
  return limit > 0 && hub.db.countActiveSessions() >= limit;
}

/**
 * Stores a prompt on the session row until its start time and a free
 * concurrency slot allow the hub to send it. Unlike pause, the session was not
 * necessarily running when it was queued.
 */
export async function queueSession(
  hub: Hub,
  id: string,
  prompt: string,
  startAt?: number,
): Promise<Session> {
  if (!hub.db.getSession(id)) {
    const client = await requireClient(hub);
    await requireSession(hub, client, id);
  }

  const until = startAt !== undefined && startAt > Date.now() ? Math.round(startAt) : undefined;
  if (!hub.db.setSessionQueue(id, prompt, until)) {
    throw new OpenCodeError("Session not found", 404);
  }
  hub.db.recordTaskPrompt(id, prompt);
  broadcastSession(hub, id);
  return hub.db.getSession(id)!;
}

/** Removes a queued prompt without sending it. */
export async function cancelQueuedSession(hub: Hub, id: string): Promise<Session> {
  const session = hub.db.getSession(id);
  if (!session) throw new OpenCodeError("Session not found", 404);
  hub.db.clearSessionQueue(id);
  broadcastSession(hub, id);
  return hub.db.getSession(id)!;
}

/** Sends the prompt stored on a queued session. Callers enforce the limit. */
async function sendQueuedPrompt(hub: Hub, id: string, prompt: string): Promise<boolean> {
  const client = await requireClient(hub);
  await client.promptSession(id, prompt);
  hub.db.clearSessionQueue(id);
  hub.db.recordTaskPrompt(id, prompt);
  hub.db.markActive(id, true, Date.now());
  broadcastSession(hub, id);
  return true;
}

/**
 * Starts one queued task. `force` is used by the explicit "Start now" action,
 * which may temporarily exceed the concurrency limit.
 */
export async function startQueuedSession(
  hub: Hub,
  id: string,
  force = false,
): Promise<Session> {
  const session = hub.db.getSession(id);
  if (!session) throw new OpenCodeError("Session not found", 404);
  const prompt = session.task?.queuedPrompt;
  if (!prompt) {
    hub.db.clearSessionQueue(id);
    broadcastSession(hub, id);
    return hub.db.getSession(id)!;
  }
  if (!force && shouldQueuePrompt(hub, id)) return session;

  await sendQueuedPrompt(hub, id, prompt);
  return hub.db.getSession(id)!;
}

/**
 * Starts due queued tasks in queue order while a concurrency slot is free.
 * Failures leave the prompt queued so the next fast loop retries.
 */
export async function startQueuedSessions(hub: Hub): Promise<void> {
  let active = hub.db.countActiveSessions();
  const limit = hub.config.maxConcurrentAgents;

  for (const item of hub.db.getDueQueuedSessions()) {
    if (limit > 0 && active >= limit) break;
    if (hub.resuming.has(item.id)) continue;

    hub.resuming.add(item.id);
    try {
      await sendQueuedPrompt(hub, item.id, item.prompt);
      active += 1;
      hub.log("info", `Started queued session ${item.id}`);
    } catch (error) {
      if (error instanceof OpenCodeError && error.status === 404) {
        hub.db.clearSessionQueue(item.id);
        broadcastSession(hub, item.id);
      } else {
        hub.noteError(error);
      }
    } finally {
      hub.resuming.delete(item.id);
    }
  }
}

/**
 * Continues every timed pause whose deadline has passed. Failures leave the
 * control row in place so the next loop retries, which also covers OpenCode
 * being offline when the timer fires. Deleted sessions are released.
 */
export async function resumeDueSessions(hub: Hub): Promise<void> {
  for (const { id } of hub.db.getDuePauses()) {
    if (hub.resuming.has(id)) continue;
    hub.resuming.add(id);
    try {
      await continueSession(hub, id);
      hub.log("info", `Resumed paused session ${id}`);
    } catch (error) {
      if (error instanceof OpenCodeError && error.status === 404) {
        hub.db.clearSessionControl(id);
        broadcastSession(hub, id);
      } else {
        hub.noteError(error);
      }
    } finally {
      hub.resuming.delete(id);
    }
  }
}
