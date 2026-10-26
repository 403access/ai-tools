import type { Database } from "bun:sqlite";
import type { Session } from "../types.ts";
import type { ChangeLog } from "./projects.ts";
import { getSession } from "./sessions.ts";
import { text, type Row } from "./rows.ts";

export type TaskResolution = "open" | "done" | "dismissed";

/**
 * Resolves a board task. Marking it open clears the resolution so the derived
 * status becomes "review" (or "working" while the session is still running).
 * The row is adopted on first use, which lets a prompt reopen a session that
 * predates the task board.
 */
export function setTaskStatus(
  db: Database,
  log: ChangeLog,
  id: string,
  status: TaskResolution,
  now = Date.now(),
): Session | null {
  const row = db.query("SELECT id, task_created, task_status FROM sessions WHERE id = ?").get(id) as Row | null;
  if (!row) return null;

  const doneAt = status === "open" ? null : now;
  // Accepting or dismissing a queued task also drops its pending prompt.
  // Reopening leaves the queue alone so the user can keep waiting for a slot.
  const clearQueue = status !== "open";
  db.prepare(
    `UPDATE sessions
     SET task_created = COALESCE(task_created, ?),
         task_status = ?,
         task_done_at = ?,
         queued_at = CASE WHEN ? THEN NULL ELSE queued_at END,
         queued_until = CASE WHEN ? THEN NULL ELSE queued_until END,
         queued_prompt = CASE WHEN ? THEN NULL ELSE queued_prompt END,
         synced_at = ?
     WHERE id = ?`,
  ).run(
    now,
    status,
    doneAt,
    clearQueue ? 1 : 0,
    clearQueue ? 1 : 0,
    clearQueue ? 1 : 0,
    now,
    id,
  );
  log.logChange("session", id);
  return getSession(db, id);
}

/**
 * Remembers text from a prompt sent through the hub. It is used only to derive
 * labels, and is capped so a long prompt cannot bloat every sync payload.
 */
export function recordTaskPrompt(
  db: Database,
  log: ChangeLog,
  id: string,
  prompt: string,
  now = Date.now(),
): void {
  const row = db.query("SELECT task_created, task_context FROM sessions WHERE id = ?").get(id) as Row | null;
  if (!row) return;

  const previous = text(row.task_context) ?? "";
  const extra = prompt.trim();
  const combined = extra ? (previous ? `${previous}\n${extra}` : extra) : previous;
  const context = combined.slice(-4_000);
  const hasTask = row.task_created !== null && row.task_created !== undefined;

  db.prepare(
    `UPDATE sessions
     SET task_created = COALESCE(task_created, ?),
         task_status = 'open',
         task_done_at = NULL,
         task_context = ?,
         synced_at = ?
     WHERE id = ?`,
  ).run(now, context, now, id);

  // New prompts reopen a resolved task and change its labels, so every prompt
  // is a visible change for the board even when the session row itself did not
  // move.
  if (hasTask || extra) log.logChange("session", id);
}
