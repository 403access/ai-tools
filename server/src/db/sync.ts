import type { Database } from "bun:sqlite";
import type { SyncResponse } from "../types.ts";
import { optionalNumber, rowToProject, rowToSession, type Row } from "./rows.ts";
import { getActiveSessionIDs, getSessions } from "./sessions.ts";
import { getProjects } from "./projects.ts";

export function syncRevision(db: Database): number {
  const row = db.query("SELECT COALESCE(MAX(rev), 0) AS rev FROM sync_log").get() as Row;
  return typeof row.rev === "number" ? row.rev : 0;
}

/**
 * Everything a client needs to catch up from `since`. When the client is new,
 * ahead of the hub (its database was reset), or older than the retained feed,
 * the response is a full snapshot instead of a delta.
 */
export function getSync(db: Database, since?: number): SyncResponse {
  const revision = syncRevision(db);
  const minRow = db.query("SELECT MIN(rev) AS rev FROM sync_log").get() as Row | null;
  const oldest = optionalNumber(minRow?.rev);

  const requested = typeof since === "number" && Number.isFinite(since) ? Math.floor(since) : undefined;
  const full =
    requested === undefined ||
    requested <= 0 ||
    requested > revision ||
    (oldest !== undefined && requested < oldest - 1);

  if (full) {
    return {
      revision,
      full: true,
      sessions: getSessions(db, { limit: 5_000 }),
      deletedSessions: [],
      projects: getProjects(db),
      deletedProjects: [],
      active: getActiveSessionIDs(db),
    };
  }

  const changedSessions = db
    .query(
      `SELECT * FROM sessions
       WHERE id IN (
         SELECT entity_id FROM sync_log
         WHERE kind = 'session' AND deleted = 0 AND rev > ? AND rev <= ?
       )
       ORDER BY updated DESC`,
    )
    .all(requested, revision) as Row[];

  const deletedSessions = db
    .query(
      `SELECT DISTINCT entity_id AS id FROM sync_log
       WHERE kind = 'session' AND deleted = 1 AND rev > ? AND rev <= ?
         AND entity_id NOT IN (SELECT id FROM sessions)`,
    )
    .all(requested, revision) as Row[];

  const changedProjects = db
    .query(
      `SELECT * FROM projects
       WHERE id IN (
         SELECT entity_id FROM sync_log
         WHERE kind = 'project' AND deleted = 0 AND rev > ? AND rev <= ?
       )
       ORDER BY updated DESC`,
    )
    .all(requested, revision) as Row[];

  const deletedProjects = db
    .query(
      `SELECT DISTINCT entity_id AS id FROM sync_log
       WHERE kind = 'project' AND deleted = 1 AND rev > ? AND rev <= ?
         AND entity_id NOT IN (SELECT id FROM projects)`,
    )
    .all(requested, revision) as Row[];

  return {
    revision,
    full: false,
    sessions: changedSessions.map(rowToSession),
    deletedSessions: deletedSessions.map((row) => String(row.id)),
    projects: changedProjects.map(rowToProject),
    deletedProjects: deletedProjects.map((row) => String(row.id)),
    active: getActiveSessionIDs(db),
  };
}
