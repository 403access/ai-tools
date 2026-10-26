import type { Database } from "bun:sqlite";
import { ZERO_TOKENS, type Session, type TokenUsage } from "../types.ts";
import { taskEpoch } from "./meta.ts";
import type { ChangeLog } from "./projects.ts";
import { number, optionalNumber, rowToSession, type Row } from "./rows.ts";

export interface SessionQuery {
  limit?: number;
  offset?: number;
  project?: string;
  parentID?: string;
  active?: boolean;
  order?: "asc" | "desc";
  q?: string;
  /** Only sessions that the user manages on the task board. */
  tasksOnly?: boolean;
}

export function upsertSessions(
  db: Database,
  log: ChangeLog,
  sessions: Session[],
  now = Date.now(),
): void {
  const insert = db.prepare(`
    INSERT INTO sessions (
      id, parent_id, project_id, agent, model, cost, tokens, outcome,
      created, updated, idle, viewed, archived, title, subpath, directory,
      fork_session_id, fork_boundary, active, task_created, task_status, synced_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      parent_id = excluded.parent_id,
      project_id = excluded.project_id,
      agent = excluded.agent,
      model = excluded.model,
      cost = excluded.cost,
      tokens = excluded.tokens,
      outcome = excluded.outcome,
      created = excluded.created,
      updated = excluded.updated,
      idle = excluded.idle,
      viewed = excluded.viewed,
      archived = excluded.archived,
      title = excluded.title,
      subpath = excluded.subpath,
      directory = excluded.directory,
      fork_session_id = COALESCE(excluded.fork_session_id, sessions.fork_session_id),
      fork_boundary = COALESCE(excluded.fork_boundary, sessions.fork_boundary),
      synced_at = excluded.synced_at
    WHERE sessions.parent_id IS NOT excluded.parent_id
       OR sessions.project_id IS NOT excluded.project_id
       OR sessions.agent IS NOT excluded.agent
       OR sessions.model IS NOT excluded.model
       OR sessions.cost IS NOT excluded.cost
       OR sessions.tokens IS NOT excluded.tokens
       OR sessions.outcome IS NOT excluded.outcome
       OR sessions.created IS NOT excluded.created
       OR sessions.updated IS NOT excluded.updated
       OR sessions.idle IS NOT excluded.idle
       OR sessions.viewed IS NOT excluded.viewed
       OR sessions.archived IS NOT excluded.archived
       OR sessions.title IS NOT excluded.title
       OR sessions.subpath IS NOT excluded.subpath
       OR sessions.directory IS NOT excluded.directory
       OR sessions.fork_session_id IS NOT COALESCE(excluded.fork_session_id, sessions.fork_session_id)
       OR sessions.fork_boundary IS NOT COALESCE(excluded.fork_boundary, sessions.fork_boundary)
  `);
  const run = db.transaction((items: Session[]) => {
    const epoch = taskEpoch(db);
    for (const session of items) {
      // Only top-level sessions created after the task board was installed
      // become tasks. Subagents are implementation detail, and older history
      // stays out of the board unless the user prompts it through the hub.
      const tracked = !session.parentID && number(session.time?.created) >= epoch;
      const result = insert.run(
        session.id,
        session.parentID ?? null,
        session.projectID ?? "",
        session.agent ?? null,
        session.model ? JSON.stringify(session.model) : null,
        number(session.cost),
        JSON.stringify(session.tokens ?? ZERO_TOKENS),
        session.outcome ?? null,
        number(session.time?.created),
        number(session.time?.updated),
        session.time?.idle ?? null,
        session.time?.viewed ?? null,
        session.time?.archived ?? null,
        session.title ?? null,
        session.subpath ?? null,
        session.location?.directory ?? null,
        session.fork?.sessionID ?? null,
        session.fork?.boundary ? JSON.stringify(session.fork.boundary) : null,
        tracked ? now : null,
        tracked ? "open" : null,
        now,
      );
      // `changes` is zero when the WHERE clause skipped an identical row, so
      // the feed only records sessions that actually moved.
      if (result.changes > 0) log.logChange("session", session.id);
    }
  });
  run(sessions);
}

export function setActive(db: Database, ids: Set<string>, now = Date.now()): void {
  const run = db.transaction(() => {
    db.exec("UPDATE sessions SET active = 0 WHERE active = 1");
    const mark = db.prepare("UPDATE sessions SET active = 1, synced_at = ? WHERE id = ?");
    for (const id of ids) mark.run(now, id);
  });
  run();
}

export function markActive(db: Database, id: string, active: boolean, now = Date.now()): void {
  db.prepare("UPDATE sessions SET active = ?, synced_at = ? WHERE id = ?").run(active ? 1 : 0, now, id);
}

export function updateSessionUsage(
  db: Database,
  log: ChangeLog,
  id: string,
  cost: number | undefined,
  tokens: TokenUsage | undefined,
  now = Date.now(),
): void {
  if (cost === undefined && tokens === undefined) return;
  const row = db.query("SELECT cost, tokens FROM sessions WHERE id = ?").get(id) as Row | null;
  if (!row) return;
  const nextCost = cost ?? number(row.cost);
  const nextTokens = tokens ? JSON.stringify(tokens) : String(row.tokens ?? "{}");
  const result = db
    .prepare(
      `UPDATE sessions SET cost = ?, tokens = ?, synced_at = ?
       WHERE id = ? AND (cost IS NOT ? OR tokens IS NOT ?)`,
    )
    .run(nextCost, nextTokens, now, id, nextCost, nextTokens);
  if (result.changes > 0) log.logChange("session", id);
}

export function getSessions(db: Database, query: SessionQuery = {}): Session[] {
  const where: string[] = [];
  const params: Array<string | number> = [];
  if (query.project) {
    where.push("project_id = ?");
    params.push(query.project);
  }
  if (query.parentID) {
    where.push("parent_id = ?");
    params.push(query.parentID);
  }
  if (query.active) {
    where.push("active = 1");
  }
  if (query.tasksOnly) {
    where.push("task_created IS NOT NULL");
  }
  if (query.q?.trim()) {
    where.push("(title LIKE ? OR directory LIKE ?)");
    const needle = `%${query.q.trim()}%`;
    params.push(needle, needle);
  }
  const limit = Math.min(Math.max(Math.floor(query.limit ?? 60), 1), 5_000);
  const offset = Math.max(Math.floor(query.offset ?? 0), 0);
  const order = query.order === "asc" ? "ASC" : "DESC";
  const sql = `
    SELECT * FROM sessions
    ${where.length ? "WHERE " + where.join(" AND ") : ""}
    ORDER BY updated ${order}
    LIMIT ? OFFSET ?
  `;
  params.push(limit, offset);
  return (db.query(sql).all(...params) as Row[]).map(rowToSession);
}

export function getSession(db: Database, id: string): Session | null {
  const row = db.query("SELECT * FROM sessions WHERE id = ?").get(id) as Row | null;
  return row ? rowToSession(row) : null;
}

/** Forks of one session, newest first. */
export function getForks(db: Database, sessionID: string, limit = 50): Session[] {
  const capped = Math.min(Math.max(Math.floor(limit), 1), 500);
  const rows = db
    .query(
      `SELECT * FROM sessions
       WHERE fork_session_id = ?
       ORDER BY updated DESC
       LIMIT ?`,
    )
    .all(sessionID, capped) as Row[];
  return rows.map(rowToSession);
}

export function getActiveSessionIDs(db: Database): string[] {
  return getSessions(db, { active: true, limit: 5_000 }).map((session) => session.id);
}
