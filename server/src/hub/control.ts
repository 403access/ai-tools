import { OpenCodeError } from "../opencode.ts";
import type { Hub } from "../hub.ts";
import type { Session } from "../types.ts";

/** Text sent when the user (or a timer) continues a held session. */
export const CONTINUE_PROMPT = "continue";

/** Longest timed pause accepted by the hub. */
export const MAX_PAUSE_MS = 30 * 24 * 60 * 60 * 1000;

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

  await client.promptSession(id, CONTINUE_PROMPT);
  hub.db.clearSessionControl(id);
  hub.db.markActive(id, true, Date.now());
  hub.db.recordTaskPrompt(id, CONTINUE_PROMPT);
  broadcastSession(hub, id);
  return hub.db.getSession(id)!;
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
