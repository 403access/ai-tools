import type { Database } from "bun:sqlite";
import type { SessionStats, ToolFailure, ToolTotals, ToolsSummary, ToolUsage } from "../types.ts";
import { getMessageSync } from "./messages.ts";
import { median, number, text, type Row } from "./rows.ts";
import { getSession } from "./sessions.ts";

/**
 * Per-session stats from cached messages and indexed tool calls. Callers that
 * need complete numbers should hydrate the message history first.
 */
export function getSessionStats(db: Database, sessionID: string): SessionStats | null {
  const session = getSession(db, sessionID);
  if (!session) return null;

  const counts = db
    .query(
      `SELECT
         COUNT(*) AS total,
         SUM(CASE WHEN type IN ('user', 'synthetic') THEN 1 ELSE 0 END) AS prompts,
         SUM(CASE WHEN type NOT IN ('user', 'synthetic') THEN 1 ELSE 0 END) AS steps
       FROM messages WHERE session_id = ?`,
    )
    .get(sessionID) as Row;

  const children = db
    .query("SELECT COUNT(*) AS n FROM sessions WHERE parent_id = ?")
    .get(sessionID) as Row;

  const files = db
    .query(
      `SELECT
         COUNT(DISTINCT file) AS files,
         SUM(additions) AS additions,
         SUM(deletions) AS deletions
       FROM changes WHERE session_id = ?`,
    )
    .get(sessionID) as Row;

  const sync = getMessageSync(db, sessionID);
  const created = number(session.time.created);
  const updated = number(session.time.updated);
  const stats: SessionStats = {
    sessionID,
    prompts: number(counts.prompts),
    steps: number(counts.steps),
    subagents: number(children.n),
    messages: number(counts.total),
    tokens: session.tokens,
    cost: session.cost,
    tools: getSessionTools(db, sessionID),
    failures: getSessionFailures(db, sessionID),
    files: {
      files: number(files.files),
      additions: number(files.additions),
      deletions: number(files.deletions),
    },
    time: { created, updated, duration: Math.max(0, updated - created) },
    complete: sync?.complete ?? false,
  };
  if (session.time.idle !== undefined) stats.time.idle = session.time.idle;
  return stats;
}

function getSessionTools(db: Database, sessionID: string): ToolsSummary {
  const rows = db
    .query(
      `SELECT
         name,
         COUNT(*) AS calls,
         SUM(CASE WHEN outcome = 'succeeded' THEN 1 ELSE 0 END) AS succeeded,
         SUM(CASE WHEN outcome = 'failed' THEN 1 ELSE 0 END) AS failed,
         SUM(CASE WHEN outcome = 'unfinished' THEN 1 ELSE 0 END) AS unfinished
       FROM tool_calls
       WHERE session_id = ?
       GROUP BY name
       ORDER BY calls DESC, name ASC`,
    )
    .all(sessionID) as Row[];

  const totals: ToolTotals = { calls: 0, succeeded: 0, failed: 0, unfinished: 0 };
  const durationRows = db
    .query(
      `SELECT name, (completed - ran) AS duration
       FROM tool_calls
       WHERE session_id = ? AND completed IS NOT NULL AND ran IS NOT NULL
       ORDER BY name ASC, duration ASC`,
    )
    .all(sessionID) as Row[];

  const durations = new Map<string, number[]>();
  for (const row of durationRows) {
    const name = String(row.name);
    const duration = number(row.duration, -1);
    if (duration < 0) continue;
    const list = durations.get(name) ?? [];
    list.push(duration);
    durations.set(name, list);
  }

  const usage: ToolUsage[] = rows.map((row) => {
    const name = String(row.name);
    const calls = number(row.calls);
    const succeeded = number(row.succeeded);
    const failed = number(row.failed);
    const unfinished = number(row.unfinished);
    totals.calls += calls;
    totals.succeeded += succeeded;
    totals.failed += failed;
    totals.unfinished += unfinished;
    const item: ToolUsage = { name, calls, succeeded, failed, unfinished };
    const p50 = median(durations.get(name) ?? []);
    if (p50 !== undefined) item.durationP50 = p50;
    return item;
  });

  return { mode: "detail", totals, usage };
}

function getSessionFailures(db: Database, sessionID: string): ToolFailure[] {
  const rows = db
    .query(
      `SELECT name, error, message_id, part_id, created
       FROM tool_calls
       WHERE session_id = ? AND outcome = 'failed'
       ORDER BY created DESC, part_id DESC
       LIMIT 10`,
    )
    .all(sessionID) as Row[];

  return rows.map((row) => {
    const failure: ToolFailure = {
      name: String(row.name ?? "tool"),
      created: number(row.created),
    };
    const error = text(row.error);
    if (error) failure.error = error;
    const messageID = text(row.message_id);
    if (messageID) failure.messageID = messageID;
    const partID = text(row.part_id);
    if (partID) failure.partID = partID;
    return failure;
  });
}
