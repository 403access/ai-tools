import type { Database } from "bun:sqlite";
import { createHash, randomUUID } from "node:crypto";
import type {
  ProjectDocAction,
  ProjectDocKind,
  ProjectDocumentation,
  ProjectDocumentationInput,
  ProjectFeatureDoc,
  TaskLabel,
} from "../types.ts";
import { classifyTaskAction, classifyTaskLabels } from "./taskLabels.ts";
import { number, text, type Row } from "./rows.ts";

/**
 * Project documentation is a small, append-only record of what a project's
 * prompts changed. Each entry keeps the derived task labels plus the task and
 * session it came from, so the Docs tab can explain a feature without asking a
 * model or re-reading the conversation.
 */

const MAX_ENTRIES_PER_KIND = 200;
const MAX_DETAIL = 2_000;
const MAX_TITLE = 120;
const MAX_BRIEF = 4_000;

function parseLabels(raw: unknown): TaskLabel[] {
  if (typeof raw !== "string" || !raw) return [];
  try {
    const value = JSON.parse(raw);
    if (!Array.isArray(value)) return [];
    return value.filter((item): item is TaskLabel => {
      return Boolean(
        item
        && typeof item === "object"
        && typeof item.id === "string"
        && typeof item.title === "string"
        && typeof item.kind === "string",
      );
    });
  } catch {
    return [];
  }
}

function rowToEntry(row: Row): ProjectFeatureDoc {
  return {
    id: String(row.id),
    projectID: String(row.project_id ?? ""),
    sessionID: String(row.session_id ?? ""),
    taskTitle: text(row.task_title) ?? "",
    title: text(row.title) ?? "",
    detail: text(row.detail) ?? "",
    action: (text(row.action) as ProjectDocAction) ?? "update",
    kind: (text(row.kind) as ProjectDocKind) ?? "technical",
    category: text(row.category) ?? "change",
    categoryTitle: text(row.category_title) ?? "Change",
    labels: parseLabels(row.labels),
    createdAt: number(row.created),
    updatedAt: number(row.updated),
  };
}

function getEntries(
  db: Database,
  projectID: string,
  kind: ProjectDocKind,
): ProjectFeatureDoc[] {
  return (
    db.query(
      `SELECT * FROM project_doc_entries
       WHERE project_id = ? AND kind = ?
       ORDER BY created DESC, id DESC`,
    ).all(projectID, kind) as Row[]
  ).map(rowToEntry);
}

export function getProjectDocumentation(
  db: Database,
  projectID: string,
): ProjectDocumentation | null {
  const row = db
    .query("SELECT * FROM project_docs WHERE project_id = ?")
    .get(projectID) as Row | null;
  if (!row) return null;

  return {
    projectID,
    description: text(row.description) ?? "",
    mission: text(row.mission) ?? "",
    vision: text(row.vision) ?? "",
    productFeatures: getEntries(db, projectID, "product"),
    technicalFeatures: getEntries(db, projectID, "technical"),
    updatedAt: number(row.updated_at),
  };
}

/**
 * Creates the editable brief on first use. The caller can pass a summary read
 * from the project's README so the page opens with useful context instead of
 * three empty fields. Existing text is never overwritten here.
 */
export function createProjectDocumentation(
  db: Database,
  projectID: string,
  description = "",
  now = Date.now(),
): ProjectDocumentation {
  db.prepare(
    `INSERT OR IGNORE INTO project_docs
       (project_id, description, mission, vision, updated_at)
     VALUES (?, ?, '', '', ?)`,
  ).run(projectID, description.trim(), now);

  // The prompt recorder may have inserted entries before the first page open.
  db.prepare(
    "UPDATE project_docs SET updated_at = MAX(updated_at, ?) WHERE project_id = ?",
  ).run(now, projectID);

  return getProjectDocumentation(db, projectID)!;
}

/** Updates one or more editable brief fields and returns the fresh page. */
export function updateProjectDocumentation(
  db: Database,
  projectID: string,
  input: ProjectDocumentationInput,
  now = Date.now(),
): ProjectDocumentation | null {
  const row = db
    .query("SELECT description, mission, vision FROM project_docs WHERE project_id = ?")
    .get(projectID) as Row | null;
  if (!row) return null;

  const normalise = (value: unknown, fallback: string): string => {
    if (value === undefined) return fallback;
    if (typeof value !== "string") return fallback;
    return value.trim().slice(0, MAX_BRIEF);
  };

  db.prepare(
    `UPDATE project_docs
     SET description = ?, mission = ?, vision = ?, updated_at = ?
     WHERE project_id = ?`,
  ).run(
    normalise(input.description, text(row.description) ?? ""),
    normalise(input.mission, text(row.mission) ?? ""),
    normalise(input.vision, text(row.vision) ?? ""),
    now,
    projectID,
  );

  return getProjectDocumentation(db, projectID);
}

function collapse(value: string): string {
  return value.replace(/\s+/g, " ").trim();
}

function firstLine(value: string): string {
  return collapse(value.split(/\r?\n/, 1)[0] ?? "");
}

function documentTitle(title: string | undefined, prompt: string): string {
  const curated = collapse(title ?? "");
  if (curated) return curated.slice(0, MAX_TITLE);
  return (firstLine(prompt) || "Prompt").slice(0, MAX_TITLE);
}

function documentKind(type: string | undefined, scope: string | undefined): ProjectDocKind {
  if (scope === "product") return "product";
  if (scope === "technical" || scope === "infrastructure") return "technical";
  // A feature or bug without an explicit scope is usually what the user sees.
  if (type === "feature" || type === "bug") return "product";
  return "technical";
}

function pruneEntries(db: Database, projectID: string, kind: ProjectDocKind): void {
  db.prepare(
    `DELETE FROM project_doc_entries
     WHERE project_id = ?
       AND kind = ?
       AND id NOT IN (
         SELECT id FROM project_doc_entries
         WHERE project_id = ? AND kind = ?
         ORDER BY created DESC, id DESC
         LIMIT ?
       )`,
  ).run(projectID, kind, projectID, kind, MAX_ENTRIES_PER_KIND);
}

/**
 * Records the documentation implied by one new prompt. The same prompt in the
 * same session updates its existing entry (a queued prompt is recorded twice:
 * once when parked and once when sent), so a queued task does not leave two
 * entries behind.
 */
export function recordPromptDocumentation(
  db: Database,
  sessionID: string,
  prompt: string,
  now = Date.now(),
): ProjectFeatureDoc | null {
  const session = db
    .query(
      `SELECT id, project_id, parent_id, title
       FROM sessions WHERE id = ?`,
    )
    .get(sessionID) as Row | null;
  if (!session) return null;

  const projectID = text(session.project_id) ?? "";
  if (!projectID) return null;
  // Child sessions are subagents; their prompts describe implementation steps,
  // not user-visible project changes.
  if (text(session.parent_id)) return null;

  const promptText = prompt.trim();
  if (!promptText || promptText.toLowerCase() === "continue") return null;

  const titleValue = text(session.title);
  const labels = classifyTaskLabels(titleValue, promptText);
  const type = labels.find((label) => label.kind === "type");
  const scope = labels.find((label) => label.kind === "scope");
  const action = classifyTaskAction(titleValue, promptText);
  const kind = documentKind(type?.id, scope?.id);
  const title = documentTitle(titleValue, promptText);
  const taskTitle = collapse(titleValue ?? "") || title;
  const detail = promptText.slice(0, MAX_DETAIL);
  const promptHash = createHash("sha256").update(promptText).digest("hex").slice(0, 32);
  const id = `doc_${randomUUID()}`;

  db.prepare(
    `INSERT INTO project_doc_entries
       (id, project_id, session_id, prompt_hash, kind, action, category,
        category_title, labels, title, detail, task_title, created, updated)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(project_id, session_id, prompt_hash) DO UPDATE SET
       kind = excluded.kind,
       action = excluded.action,
       category = excluded.category,
       category_title = excluded.category_title,
       labels = excluded.labels,
       title = excluded.title,
       detail = excluded.detail,
       task_title = excluded.task_title,
       updated = excluded.updated`,
  ).run(
    id,
    projectID,
    sessionID,
    promptHash,
    kind,
    action,
    type?.id ?? "change",
    type?.title ?? "Change",
    JSON.stringify(labels),
    title,
    detail,
    taskTitle,
    now,
    now,
  );

  db.prepare("UPDATE project_docs SET updated_at = ? WHERE project_id = ?").run(
    now,
    projectID,
  );
  pruneEntries(db, projectID, kind);

  const row = db
    .query(
      `SELECT * FROM project_doc_entries
       WHERE project_id = ? AND session_id = ? AND prompt_hash = ?`,
    )
    .get(projectID, sessionID, promptHash) as Row | null;
  return row ? rowToEntry(row) : null;
}
