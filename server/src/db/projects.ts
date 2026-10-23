import type { Database } from "bun:sqlite";
import type { Project } from "../types.ts";
import { number, optionalNumber, rowToProject, type Row } from "./rows.ts";

export interface ChangeLog {
  logChange(kind: "session" | "project", id: string, deleted?: boolean): void;
}

export function replaceProjects(db: Database, log: ChangeLog, projects: Project[], now = Date.now()): void {
  upsertProjects(db, log, projects, now);

  // The upstream project list is authoritative, so anything missing locally
  // has been removed. Record a tombstone for the clients before dropping it.
  const keep = new Set(projects.map((project) => project.id));
  const rows = db.query("SELECT id FROM projects").all() as Row[];
  const remove = db.prepare("DELETE FROM projects WHERE id = ?");
  const run = db.transaction(() => {
    for (const row of rows) {
      const id = String(row.id);
      if (keep.has(id)) continue;
      remove.run(id);
      log.logChange("project", id, true);
    }
  });
  run();
}

export function upsertProjects(db: Database, log: ChangeLog, projects: Project[], now = Date.now()): void {
  const insert = db.prepare(`
    INSERT INTO projects (id, canonical, vcs, name, created, updated, active, sandboxes, synced_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      canonical = excluded.canonical,
      vcs = excluded.vcs,
      name = excluded.name,
      created = excluded.created,
      updated = excluded.updated,
      active = excluded.active,
      sandboxes = excluded.sandboxes,
      synced_at = excluded.synced_at
    WHERE projects.canonical IS NOT excluded.canonical
       OR projects.vcs IS NOT excluded.vcs
       OR projects.name IS NOT excluded.name
       OR projects.created IS NOT excluded.created
       OR projects.updated IS NOT excluded.updated
       OR projects.active IS NOT excluded.active
       OR projects.sandboxes IS NOT excluded.sandboxes
  `);
  const run = db.transaction((items: Project[]) => {
    for (const project of items) {
      const result = insert.run(
        project.id,
        project.canonical ?? "",
        project.vcs ?? null,
        project.name ?? null,
        number(project.time?.created),
        number(project.time?.updated),
        optionalNumber(project.time?.active) ?? null,
        JSON.stringify(project.sandboxes ?? []),
        now,
      );
      if (result.changes > 0) log.logChange("project", project.id);
    }
  });
  run(projects);
}

export function getProjects(db: Database): Project[] {
  return (db.query("SELECT * FROM projects ORDER BY updated DESC").all() as Row[]).map(rowToProject);
}

export function getProject(db: Database, id: string): Project | null {
  const row = db.query("SELECT * FROM projects WHERE id = ?").get(id) as Row | null;
  return row ? rowToProject(row) : null;
}
