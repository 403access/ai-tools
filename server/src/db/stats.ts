import type { Database } from "bun:sqlite";
import type { GoUsage, Stats } from "../types.ts";
import { number, optionalNumber, text, type Row } from "./rows.ts";

export interface CachedStats {
  data: Stats;
  fetchedAt: number;
}

export interface CachedUsage {
  data: GoUsage | null;
  fetchedAt: number | null;
  attemptedAt: number | null;
  error: string | null;
}

export function putStats(db: Database, scope: string, payload: Stats, now = Date.now()): void {
  db.prepare(
    `INSERT INTO stats (scope, payload, fetched_at) VALUES (?, ?, ?)
     ON CONFLICT(scope) DO UPDATE SET payload = excluded.payload, fetched_at = excluded.fetched_at`,
  ).run(scope, JSON.stringify(payload), now);
}

export function getStats(db: Database, scope: string): CachedStats | null {
  const row = db.query("SELECT payload, fetched_at FROM stats WHERE scope = ?").get(scope) as Row | null;
  if (!row) return null;
  try {
    return { data: JSON.parse(String(row.payload)) as Stats, fetchedAt: number(row.fetched_at) };
  } catch {
    return null;
  }
}

export function putUsage(
  db: Database,
  payload: GoUsage | null,
  fetchedAt: number | null,
  error: string | null,
  now = Date.now(),
): void {
  db.prepare(
    `INSERT INTO usage (id, payload, fetched_at, attempted_at, error) VALUES (1, ?, ?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       payload = excluded.payload,
       fetched_at = excluded.fetched_at,
       attempted_at = excluded.attempted_at,
       error = excluded.error`,
  ).run(payload ? JSON.stringify(payload) : null, fetchedAt, now, error);
}

/** Records a failed attempt while keeping the last good payload. */
export function putUsageError(db: Database, error: string, now = Date.now()): void {
  db.prepare(
    `INSERT INTO usage (id, payload, fetched_at, attempted_at, error) VALUES (1, NULL, NULL, ?, ?)
     ON CONFLICT(id) DO UPDATE SET attempted_at = excluded.attempted_at, error = excluded.error`,
  ).run(now, error);
}

export function getUsage(db: Database): CachedUsage {
  const row = db.query("SELECT * FROM usage WHERE id = 1").get() as Row | null;
  if (!row) return { data: null, fetchedAt: null, attemptedAt: null, error: null };
  let payload: GoUsage | null = null;
  if (typeof row.payload === "string" && row.payload) {
    try {
      payload = JSON.parse(row.payload) as GoUsage;
    } catch {
      payload = null;
    }
  }
  return {
    data: payload,
    fetchedAt: optionalNumber(row.fetched_at) ?? null,
    attemptedAt: optionalNumber(row.attempted_at) ?? null,
    error: text(row.error) ?? null,
  };
}

export function counts(db: Database): { sessions: number; messages: number; projects: number } {
  const row = db
    .query(
      `SELECT
         (SELECT COUNT(*) FROM sessions) AS sessions,
         (SELECT COUNT(*) FROM messages) AS messages,
         (SELECT COUNT(*) FROM projects) AS projects`,
    )
    .get() as Row;
  return {
    sessions: number(row.sessions),
    messages: number(row.messages),
    projects: number(row.projects),
  };
}
