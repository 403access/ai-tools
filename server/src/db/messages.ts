import type { Database } from "bun:sqlite";
import type { FileDiff, MessageCursor, SessionMessage } from "../types.ts";
import { decodeMessageCursor, encodeMessageCursor } from "./cursor.ts";
import { parseFileDiffs, toolErrorText, toolOutcome } from "./parsing.ts";
import { number, optionalNumber, rowToMessage, text, type Row } from "./rows.ts";
import { getSession } from "./sessions.ts";

export interface MessagePage {
  data: SessionMessage[];
  cursor?: MessageCursor;
}

export interface MessageSync {
  syncedAt: number;
  oldestCursor: string | null;
  complete: boolean;
}

/** Records a session's cached messages and the changes/tools they contain. */
export function upsertMessages(
  db: Database,
  sessionID: string,
  messages: SessionMessage[],
  now = Date.now(),
): void {
  const insert = db.prepare(`
    INSERT INTO messages (
      id, session_id, type, created, streamed, completed, text, content,
      model, agent, cost, tokens, synced_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(session_id, id) DO UPDATE SET
      type = excluded.type,
      created = excluded.created,
      streamed = excluded.streamed,
      completed = excluded.completed,
      text = COALESCE(excluded.text, messages.text),
      content = COALESCE(excluded.content, messages.content),
      model = COALESCE(excluded.model, messages.model),
      agent = COALESCE(excluded.agent, messages.agent),
      cost = COALESCE(excluded.cost, messages.cost),
      tokens = COALESCE(excluded.tokens, messages.tokens),
      synced_at = excluded.synced_at
  `);
  const directory = getSession(db, sessionID)?.location.directory;
  const run = db.transaction((items: SessionMessage[]) => {
    for (const message of items) {
      insert.run(
        message.id,
        sessionID,
        message.type ?? "assistant",
        number(message.time?.created),
        message.time?.streamed ?? null,
        message.time?.completed ?? null,
        message.text ?? null,
        message.content ? JSON.stringify(message.content) : null,
        message.model ? JSON.stringify(message.model) : null,
        message.agent ?? null,
        message.cost ?? null,
        message.tokens ? JSON.stringify(message.tokens) : null,
        now,
      );
      storeChanges(
        db,
        sessionID,
        message.id,
        message.content ?? [],
        number(message.time?.created),
        directory,
        now,
      );
      if (message.content) {
        storeToolCalls(
          db,
          sessionID,
          message.id,
          message.content,
          number(message.time?.created),
          now,
        );
      }
    }
  });
  run(messages);
}

/**
 * Indexes tool parts by name and outcome so a session's reliability can be
 * summarised without reparsing every message on each request.
 */
function storeToolCalls(
  db: Database,
  sessionID: string,
  messageID: string,
  parts: SessionMessage["content"],
  created: number,
  now: number,
): void {
  db.prepare("DELETE FROM tool_calls WHERE session_id = ? AND message_id = ?").run(sessionID, messageID);

  const insert = db.prepare(`
    INSERT INTO tool_calls (
      session_id, message_id, part_id, name, outcome, error, created, ran,
      completed, synced_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(session_id, part_id) DO UPDATE SET
      message_id = excluded.message_id,
      name = excluded.name,
      outcome = excluded.outcome,
      error = excluded.error,
      created = excluded.created,
      ran = excluded.ran,
      completed = excluded.completed,
      synced_at = excluded.synced_at
  `);

  for (const [index, part] of (parts ?? []).entries()) {
    if (!part || part.type !== "tool") continue;
    const state = part.state;
    const status = state && typeof state === "object" ? state.status : undefined;
    const outcome = toolOutcome(status);
    const partID = part.id ?? `${messageID}-${index}`;
    const when = part.time?.created ?? created;
    insert.run(
      sessionID,
      messageID,
      partID,
      part.name ?? "tool",
      outcome,
      outcome === "failed" ? (toolErrorText(state?.error) ?? "Tool call failed") : null,
      number(when),
      optionalNumber(part.time?.ran) ?? null,
      optionalNumber(part.time?.completed) ?? null,
      now,
    );
  }
}

/** Records the file patches carried by a message's tool parts. */
function storeChanges(
  db: Database,
  sessionID: string,
  messageID: string,
  parts: SessionMessage["content"],
  created: number,
  directory: string | null | undefined,
  now: number,
): void {
  const insert = db.prepare(`
    INSERT INTO changes (
      session_id, message_id, part_id, file, patch, additions, deletions,
      status, created, synced_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(session_id, part_id, file) DO UPDATE SET
      message_id = excluded.message_id,
      patch = excluded.patch,
      additions = excluded.additions,
      deletions = excluded.deletions,
      status = excluded.status,
      created = excluded.created,
      synced_at = excluded.synced_at
  `);

  for (const [index, part] of (parts ?? []).entries()) {
    const diffs = parseFileDiffs(part, directory);
    if (!diffs.length) continue;
    const partID = part.id ?? `${messageID}-${index}`;
    for (const diff of diffs) {
      insert.run(
        sessionID,
        messageID,
        partID,
        diff.file ?? "",
        diff.patch ?? "",
        diff.additions,
        diff.deletions,
        diff.status ?? null,
        created,
        now,
      );
    }
  }
}

/**
 * Rebuilds the tool-call index from already cached messages. Used by the v3
 * migration and safe to call at any time for one session.
 */
export function backfillToolCalls(db: Database, sessionID?: string, now = Date.now()): void {
  const rows = sessionID
    ? (db
        .query("SELECT id, session_id, content, created FROM messages WHERE session_id = ?")
        .all(sessionID) as Row[])
    : (db.query("SELECT id, session_id, content, created FROM messages").all() as Row[]);

  const run = db.transaction(() => {
    if (sessionID) db.prepare("DELETE FROM tool_calls WHERE session_id = ?").run(sessionID);
    for (const row of rows) {
      if (typeof row.content !== "string" || !row.content) continue;
      try {
        const parts = JSON.parse(row.content) as SessionMessage["content"];
        storeToolCalls(db, String(row.session_id), String(row.id), parts ?? [], number(row.created), now);
      } catch {
        // Ignore malformed cached content; it will be replaced on refresh.
      }
    }
  });
  run();
}

export function getChanges(db: Database, sessionID: string): FileDiff[] {
  const rows = db
    .query(
      `SELECT * FROM changes WHERE session_id = ?
       ORDER BY created DESC, part_id DESC, file ASC`,
    )
    .all(sessionID) as Row[];
  return rows.map(rowToFileDiff);
}

/**
 * Changes across a project, newest first. Sessions are joined so the client
 * can group by session without a second request.
 */
export function getProjectChanges(db: Database, projectID: string, limit = 2_000): FileDiff[] {
  const capped = Math.min(Math.max(Math.floor(limit), 1), 5_000);
  const rows = db
    .query(
      `SELECT c.*, s.title AS session_title, s.project_id AS session_project
       FROM changes c
       JOIN sessions s ON s.id = c.session_id
       WHERE s.project_id = ?
       ORDER BY c.created DESC, c.session_id ASC, c.part_id DESC, c.file ASC
       LIMIT ?`,
    )
    .all(projectID, capped) as Row[];
  return rows.map((row) => {
    const diff = rowToFileDiff(row);
    const sessionID = text(row.session_id);
    if (sessionID) diff.sessionID = sessionID;
    const title = text(row.session_title);
    if (title) diff.sessionTitle = title;
    return diff;
  });
}

function rowToFileDiff(row: Row): FileDiff {
  const diff: FileDiff = {
    additions: number(row.additions),
    deletions: number(row.deletions),
  };
  const file = text(row.file);
  if (file) diff.file = file;
  const patch = text(row.patch);
  if (patch) diff.patch = patch;
  const status = text(row.status);
  if (status === "added" || status === "deleted" || status === "modified") {
    diff.status = status;
  }
  const messageID = text(row.message_id);
  if (messageID) diff.messageID = messageID;
  const created = optionalNumber(row.created);
  if (created !== undefined) diff.created = created;
  return diff;
}

export function getMessageSync(db: Database, sessionID: string): MessageSync | null {
  const row = db.query("SELECT * FROM message_syncs WHERE session_id = ?").get(sessionID) as Row | null;
  if (!row) return null;
  return {
    syncedAt: number(row.synced_at),
    oldestCursor: text(row.oldest_cursor) ?? null,
    complete: number(row.complete) === 1,
  };
}

export function putMessageSync(db: Database, sessionID: string, sync: MessageSync): void {
  db.prepare(
    `INSERT INTO message_syncs (session_id, synced_at, oldest_cursor, complete)
     VALUES (?, ?, ?, ?)
     ON CONFLICT(session_id) DO UPDATE SET
       synced_at = excluded.synced_at,
       oldest_cursor = excluded.oldest_cursor,
       complete = excluded.complete`,
  ).run(sessionID, sync.syncedAt, sync.oldestCursor, sync.complete ? 1 : 0);
}

/** Cached messages, newest first, paged with the hub's own cursor. */
export function getMessages(db: Database, sessionID: string, limit = 100, cursor?: string | null): MessagePage {
  const capped = Math.min(Math.max(Math.floor(limit), 1), 500);
  const decoded = cursor ? decodeMessageCursor(cursor) : null;
  const rows = decoded
    ? (db
        .query(
          `SELECT * FROM messages
           WHERE session_id = ? AND (created < ? OR (created = ? AND id < ?))
           ORDER BY created DESC, id DESC LIMIT ?`,
        )
        .all(sessionID, decoded.t, decoded.t, decoded.i, capped + 1) as Row[])
    : (db
        .query(
          `SELECT * FROM messages WHERE session_id = ?
           ORDER BY created DESC, id DESC LIMIT ?`,
        )
        .all(sessionID, capped + 1) as Row[]);

  const hasMore = rows.length > capped;
  const data = rows.slice(0, capped).map(rowToMessage);
  const page: MessagePage = { data };
  if (hasMore && data.length > 0) {
    const last = data[data.length - 1]!;
    page.cursor = { next: encodeMessageCursor(last) };
  }
  return page;
}

/** Cached messages created or updated at/after `since`, newest first. */
export function getMessagesSince(db: Database, sessionID: string, since: number, limit = 500): SessionMessage[] {
  const capped = Math.min(Math.max(Math.floor(limit), 1), 1_000);
  const rows = db
    .query(
      `SELECT * FROM messages
       WHERE session_id = ?
         AND (created >= ? OR COALESCE(completed, streamed, 0) >= ?)
       ORDER BY created DESC, id DESC LIMIT ?`,
    )
    .all(sessionID, since, since, capped) as Row[];
  return rows.map(rowToMessage);
}

export function getMessageCount(db: Database, sessionID: string): number {
  const row = db.query("SELECT COUNT(*) AS n FROM messages WHERE session_id = ?").get(sessionID) as Row;
  return number(row.n);
}
