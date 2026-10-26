import type { Database } from "bun:sqlite";
import { text, type Row } from "./rows.ts";

/** Small key/value store for hub-wide settings that must survive restarts. */
export function getMeta(db: Database, key: string): string | undefined {
  const row = db.query("SELECT value FROM meta WHERE key = ?").get(key) as Row | null;
  return text(row?.value);
}

export function setMeta(db: Database, key: string, value: string): void {
  db.prepare(
    `INSERT INTO meta (key, value) VALUES (?, ?)
     ON CONFLICT(key) DO UPDATE SET value = excluded.value`,
  ).run(key, value);
}

/** Sessions created before this timestamp are not added to the task board. */
export function taskEpoch(db: Database): number {
  const value = Number.parseFloat(getMeta(db, "task_epoch") ?? "");
  return Number.isFinite(value) ? value : Date.now();
}
