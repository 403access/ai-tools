import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import {
  ZERO_TOKENS,
  type FileDiff,
  type GoUsage,
  type MessageCursor,
  type MessagesResponse,
  type ConnectedDevice,
  type Project,
  type Session,
  type SessionMessage,
  type SessionStats,
  type Stats,
  type TokenUsage,
  type ToolFailure,
  type ToolTotals,
  type ToolsSummary,
  type ToolUsage,
} from "./types.ts";

type Row = Record<string, unknown>;

export interface MessagePage {
  data: SessionMessage[];
  cursor?: MessageCursor;
}

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

export interface MessageSync {
  syncedAt: number;
  oldestCursor: string | null;
  complete: boolean;
}

/**
 * Reads the file changes OpenCode attaches to edit/write tool calls. Edits carry
 * a `state.metadata.files` array of exact patches. Writes only carry the new
 * content, so synthesize a patch from it — otherwise newly created files would
 * be invisible to the Changes views.
 */
export function parseFileDiffs(part: unknown, directory?: string | null): FileDiff[] {
  if (!part || typeof part !== "object") return [];
  const record = part as Record<string, unknown>;
  if (record.type !== "tool") return [];
  const state = record.state;
  if (!state || typeof state !== "object") return [];

  const stateRecord = state as Record<string, unknown>;
  const metadata = stateRecord.metadata;
  if (metadata && typeof metadata === "object") {
    const source = metadata as Record<string, unknown>;
    const files = Array.isArray(source.files) ? source.files : [];
    const diffs: FileDiff[] = [];
    for (const entry of files) {
      if (!entry || typeof entry !== "object") continue;
      const file = entry as Record<string, unknown>;
      const patch = text(file.patch);
      const diff: FileDiff = {
        additions: number(file.additions),
        deletions: number(file.deletions),
      };
      const name = text(file.file);
      if (name) diff.file = name;
      if (patch !== undefined) diff.patch = patch;
      const status = text(file.status);
      if (status === "added" || status === "deleted" || status === "modified") {
        diff.status = status;
      }
      diffs.push(diff);
    }
    if (diffs.length) return diffs;
  }

  // The write tool has no patch metadata; its input holds the full new content.
  const name = text(record.name)?.toLowerCase();
  const input = stateRecord.input;
  if (name === "write" && input && typeof input === "object") {
    const fields = input as Record<string, unknown>;
    const path = text(fields.path) ?? text(fields.filePath);
    const content = text(fields.content);
    if (path && content !== undefined) {
      const file = relativePath(path, directory);
      const lines = content.split("\n");
      if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
      const patch = [
        `--- /dev/null`,
        `+++ b/${file}`,
        `@@ -0,0 +1,${lines.length} @@`,
        ...lines.map((line) => `+${line}`),
      ].join("\n");
      return [{ file, patch, additions: lines.length, deletions: 0, status: "added" }];
    }
  }

  return [];
}

function relativePath(path: string, directory?: string | null): string {
  if (!directory) return path;
  const prefix = directory.endsWith("/") ? directory : `${directory}/`;
  return path.startsWith(prefix) ? path.slice(prefix.length) : path;
}

/** Collapses tool statuses into the three buckets the stats UI shows. */
export function toolOutcome(status: unknown): "succeeded" | "failed" | "unfinished" {
  const value = typeof status === "string" ? status.toLowerCase() : "";
  if (value === "completed" || value === "success" || value === "succeeded") return "succeeded";
  if (value === "error" || value === "failed" || value === "failure") return "failed";
  return "unfinished";
}

/** OpenCode reports failures as `{ type, message }` or occasionally a string. */
function toolErrorText(raw: unknown): string | undefined {
  if (typeof raw === "string") return raw;
  if (!raw || typeof raw !== "object") return undefined;
  const record = raw as Record<string, unknown>;
  if (typeof record.message === "string" && record.message) return record.message;
  try {
    return JSON.stringify(raw).slice(0, 1_000);
  } catch {
    return undefined;
  }
}

function median(values: number[]): number | undefined {
  if (!values.length) return undefined;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  const value = sorted.length % 2 === 0 ? (sorted[middle - 1]! + sorted[middle]!) / 2 : sorted[middle]!;
  return Number.isFinite(value) ? Math.round(value * 10) / 10 : undefined;
}

export interface SessionQuery {
  limit?: number;
  offset?: number;
  project?: string;
  parentID?: string;
  active?: boolean;
  order?: "asc" | "desc";
  q?: string;
}

function text(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function number(value: unknown, fallback = 0): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function optionalNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

export function parseTokens(raw: unknown): TokenUsage {
  if (typeof raw !== "string" || !raw) return { ...ZERO_TOKENS, cache: { ...ZERO_TOKENS.cache } };
  try {
    const value = JSON.parse(raw) as Partial<TokenUsage> & { cache?: Partial<TokenUsage["cache"]> };
    return {
      input: number(value.input),
      output: number(value.output),
      reasoning: number(value.reasoning),
      cache: {
        read: number(value.cache?.read),
        write: number(value.cache?.write),
      },
    };
  } catch {
    return { ...ZERO_TOKENS, cache: { ...ZERO_TOKENS.cache } };
  }
}

export function rowToSession(row: Row): Session {
  const session: Session = {
    id: String(row.id),
    projectID: String(row.project_id ?? ""),
    cost: number(row.cost),
    tokens: parseTokens(row.tokens),
    time: {
      created: number(row.created),
      updated: number(row.updated),
    },
    location: {},
  };
  const parentID = text(row.parent_id);
  if (parentID) session.parentID = parentID;
  const agent = text(row.agent);
  if (agent) session.agent = agent;
  if (typeof row.model === "string" && row.model) {
    try {
      session.model = JSON.parse(row.model);
    } catch {
      // Ignore a malformed cached model.
    }
  }
  const outcome = text(row.outcome);
  if (outcome) session.outcome = outcome;
  const idle = optionalNumber(row.idle);
  if (idle !== undefined) session.time.idle = idle;
  const viewed = optionalNumber(row.viewed);
  if (viewed !== undefined) session.time.viewed = viewed;
  const archived = optionalNumber(row.archived);
  if (archived !== undefined) session.time.archived = archived;
  const title = text(row.title);
  if (title) session.title = title;
  const subpath = text(row.subpath);
  if (subpath) session.subpath = subpath;
  const directory = text(row.directory);
  if (directory) session.location.directory = directory;
  return session;
}

export function rowToProject(row: Row): Project {
  const project: Project = {
    id: String(row.id),
    canonical: String(row.canonical ?? ""),
    time: {
      created: number(row.created),
      updated: number(row.updated),
    },
    sandboxes: [],
  };
  const vcs = text(row.vcs);
  if (vcs) project.vcs = vcs;
  const name = text(row.name);
  if (name) project.name = name;
  const active = optionalNumber(row.active);
  if (active !== undefined) project.time.active = active;
  if (typeof row.sandboxes === "string" && row.sandboxes) {
    try {
      const parsed = JSON.parse(row.sandboxes);
      if (Array.isArray(parsed)) project.sandboxes = parsed.filter((v): v is string => typeof v === "string");
    } catch {
      // Ignore malformed sandbox data.
    }
  }
  return project;
}

export function rowToMessage(row: Row): SessionMessage {
  const message: SessionMessage = {
    id: String(row.id),
    type: String(row.type ?? "assistant"),
    time: { created: number(row.created) },
  };
  const streamed = optionalNumber(row.streamed);
  if (streamed !== undefined) message.time.streamed = streamed;
  const completed = optionalNumber(row.completed);
  if (completed !== undefined) message.time.completed = completed;
  const body = text(row.text);
  if (body !== undefined) message.text = body;
  if (typeof row.content === "string" && row.content) {
    try {
      message.content = JSON.parse(row.content);
    } catch {
      // Ignore malformed cached content.
    }
  }
  if (typeof row.model === "string" && row.model) {
    try {
      message.model = JSON.parse(row.model);
    } catch {
      // Ignore malformed cached model.
    }
  }
  const agent = text(row.agent);
  if (agent) message.agent = agent;
  const cost = optionalNumber(row.cost);
  if (cost !== undefined) message.cost = cost;
  if (typeof row.tokens === "string" && row.tokens) {
    message.tokens = parseTokens(row.tokens);
  }
  return message;
}

export function encodeMessageCursor(message: SessionMessage): string {
  const payload = JSON.stringify({ t: message.time.created, i: message.id });
  return "hub." + Buffer.from(payload, "utf8").toString("base64url");
}

export function decodeMessageCursor(cursor: string): { t: number; i: string } | null {
  if (!cursor.startsWith("hub.")) return null;
  try {
    const parsed = JSON.parse(Buffer.from(cursor.slice(4), "base64url").toString("utf8")) as {
      t?: unknown;
      i?: unknown;
    };
    if (typeof parsed.t !== "number" || typeof parsed.i !== "string") return null;
    return { t: parsed.t, i: parsed.i };
  } catch {
    return null;
  }
}

export class HubDB {
  readonly db: Database;
  readonly path: string;

  constructor(path: string) {
    this.path = path;
    if (path !== ":memory:") {
      mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    }
    this.db = new Database(path, { create: true });
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec("PRAGMA busy_timeout = 5000;");
    this.migrate();
  }

  private migrate(): void {
    const version = number((this.db.query("PRAGMA user_version").get() as Row | null)?.user_version);
    if (version >= 4) return;

    if (version < 1) this.db.exec(`
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        canonical TEXT NOT NULL DEFAULT '',
        vcs TEXT,
        name TEXT,
        created REAL NOT NULL DEFAULT 0,
        updated REAL NOT NULL DEFAULT 0,
        active REAL,
        sandboxes TEXT NOT NULL DEFAULT '[]',
        synced_at REAL NOT NULL
      );

      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        project_id TEXT NOT NULL DEFAULT '',
        agent TEXT,
        model TEXT,
        cost REAL NOT NULL DEFAULT 0,
        tokens TEXT NOT NULL DEFAULT '{}',
        outcome TEXT,
        created REAL NOT NULL DEFAULT 0,
        updated REAL NOT NULL DEFAULT 0,
        idle REAL,
        viewed REAL,
        archived REAL,
        title TEXT,
        subpath TEXT,
        directory TEXT,
        active INTEGER NOT NULL DEFAULT 0,
        synced_at REAL NOT NULL
      );

      CREATE INDEX IF NOT EXISTS sessions_updated ON sessions(updated DESC);
      CREATE INDEX IF NOT EXISTS sessions_project ON sessions(project_id, updated DESC);
      CREATE INDEX IF NOT EXISTS sessions_parent ON sessions(parent_id, updated DESC);
      CREATE INDEX IF NOT EXISTS sessions_active ON sessions(active, updated DESC);

      CREATE TABLE IF NOT EXISTS messages (
        id TEXT NOT NULL,
        session_id TEXT NOT NULL,
        type TEXT NOT NULL,
        created REAL NOT NULL DEFAULT 0,
        streamed REAL,
        completed REAL,
        text TEXT,
        content TEXT,
        model TEXT,
        agent TEXT,
        cost REAL,
        tokens TEXT,
        synced_at REAL NOT NULL,
        PRIMARY KEY (session_id, id)
      );

      CREATE INDEX IF NOT EXISTS messages_session_created
        ON messages(session_id, created DESC, id DESC);

      CREATE TABLE IF NOT EXISTS stats (
        scope TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        fetched_at REAL NOT NULL
      );

      CREATE TABLE IF NOT EXISTS usage (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT,
        fetched_at REAL,
        attempted_at REAL,
        error TEXT
      );

      PRAGMA user_version = 1;
    `);

    if (version < 2) this.db.exec(`
      CREATE TABLE IF NOT EXISTS changes (
        session_id TEXT NOT NULL,
        message_id TEXT NOT NULL DEFAULT '',
        part_id TEXT NOT NULL,
        file TEXT NOT NULL,
        patch TEXT NOT NULL DEFAULT '',
        additions INTEGER NOT NULL DEFAULT 0,
        deletions INTEGER NOT NULL DEFAULT 0,
        status TEXT,
        created REAL NOT NULL DEFAULT 0,
        synced_at REAL NOT NULL,
        PRIMARY KEY (session_id, part_id, file)
      );

      CREATE INDEX IF NOT EXISTS changes_session_created
        ON changes(session_id, created DESC, part_id);
      CREATE INDEX IF NOT EXISTS changes_file ON changes(file);

      CREATE TABLE IF NOT EXISTS message_syncs (
        session_id TEXT PRIMARY KEY,
        synced_at REAL NOT NULL,
        oldest_cursor TEXT,
        complete INTEGER NOT NULL DEFAULT 0
      );

      PRAGMA user_version = 2;
    `);

    if (version < 3) {
      this.db.exec(`
        CREATE TABLE IF NOT EXISTS tool_calls (
          session_id TEXT NOT NULL,
          message_id TEXT NOT NULL DEFAULT '',
          part_id TEXT NOT NULL,
          name TEXT NOT NULL DEFAULT 'tool',
          outcome TEXT NOT NULL DEFAULT 'unfinished',
          error TEXT,
          created REAL NOT NULL DEFAULT 0,
          ran REAL,
          completed REAL,
          synced_at REAL NOT NULL,
          PRIMARY KEY (session_id, part_id)
        );

        CREATE INDEX IF NOT EXISTS tool_calls_session_created
          ON tool_calls(session_id, created DESC, part_id);
        CREATE INDEX IF NOT EXISTS tool_calls_session_outcome
          ON tool_calls(session_id, outcome, created DESC);
      `);
      // Existing cached messages predate the table, so derive their tool calls
      // once instead of waiting for OpenCode to resend every message.
      this.backfillToolCalls();
      this.db.exec("PRAGMA user_version = 3;");
    }

    if (version < 4) {
      this.db.exec(`
        CREATE TABLE IF NOT EXISTS devices (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL DEFAULT '',
          platform TEXT NOT NULL DEFAULT '',
          app_version TEXT NOT NULL DEFAULT '',
          first_seen REAL NOT NULL,
          last_seen REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS devices_last_seen ON devices(last_seen DESC);
      `);
      this.db.exec("PRAGMA user_version = 4;");
    }
  }

  /**
   * Rebuilds the tool-call index from already cached messages. Used by the v3
   * migration and safe to call at any time for one session.
   */
  private backfillToolCalls(sessionID?: string, now = Date.now()): void {
    const rows = sessionID
      ? (this.db
          .query("SELECT id, session_id, content, created FROM messages WHERE session_id = ?")
          .all(sessionID) as Row[])
      : (this.db.query("SELECT id, session_id, content, created FROM messages").all() as Row[]);

    const run = this.db.transaction(() => {
      if (sessionID) this.db.prepare("DELETE FROM tool_calls WHERE session_id = ?").run(sessionID);
      for (const row of rows) {
        if (typeof row.content !== "string" || !row.content) continue;
        try {
          const parts = JSON.parse(row.content) as SessionMessage["content"];
          this.storeToolCalls(
            String(row.session_id),
            String(row.id),
            parts ?? [],
            number(row.created),
            now,
          );
        } catch {
          // Ignore malformed cached content; it will be replaced on refresh.
        }
      }
    });
    run();
  }

  close(): void {
    this.db.close();
  }

  // MARK: - Devices

  /** Records a client app that has contacted the hub, keeping first-seen. */
  upsertDevice(
    device: { id: string; name: string; platform: string; appVersion: string },
    now = Date.now(),
  ): void {
    this.db
      .prepare(`
        INSERT INTO devices (id, name, platform, app_version, first_seen, last_seen)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          platform = excluded.platform,
          app_version = excluded.app_version,
          last_seen = excluded.last_seen
      `)
      .run(device.id, device.name, device.platform, device.appVersion, now, now);
  }

  getDevices(limit = 50): ConnectedDevice[] {
    const rows = this.db
      .query("SELECT * FROM devices ORDER BY last_seen DESC LIMIT ?")
      .all(limit) as Row[];
    return rows.map((row) => ({
      id: String(row.id),
      name: text(row.name) ?? "Unknown device",
      platform: text(row.platform) ?? "unknown",
      appVersion: text(row.app_version) ?? "",
      firstSeen: number(row.first_seen),
      lastSeen: number(row.last_seen),
      // The hub fills in the live connection state; stored rows are history.
      connected: false,
    }));
  }

  // MARK: - Projects

  replaceProjects(projects: Project[], now = Date.now()): void {
    const insert = this.db.prepare(`
      INSERT INTO projects (id, canonical, vcs, name, created, updated, active, sandboxes, synced_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    const run = this.db.transaction((items: Project[]) => {
      this.db.exec("DELETE FROM projects");
      for (const project of items) {
        insert.run(
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
      }
    });
    run(projects);
  }

  upsertProjects(projects: Project[], now = Date.now()): void {
    const insert = this.db.prepare(`
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
    `);
    const run = this.db.transaction((items: Project[]) => {
      for (const project of items) {
        insert.run(
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
      }
    });
    run(projects);
  }

  getProjects(): Project[] {
    return (this.db.query("SELECT * FROM projects ORDER BY updated DESC").all() as Row[]).map(rowToProject);
  }

  getProject(id: string): Project | null {
    const row = this.db.query("SELECT * FROM projects WHERE id = ?").get(id) as Row | null;
    return row ? rowToProject(row) : null;
  }

  // MARK: - Sessions

  upsertSessions(sessions: Session[], now = Date.now()): void {
    const insert = this.db.prepare(`
      INSERT INTO sessions (
        id, parent_id, project_id, agent, model, cost, tokens, outcome,
        created, updated, idle, viewed, archived, title, subpath, directory,
        active, synced_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
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
        synced_at = excluded.synced_at
    `);
    const run = this.db.transaction((items: Session[]) => {
      for (const session of items) {
        insert.run(
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
          now,
        );
      }
    });
    run(sessions);
  }

  setActive(ids: Set<string>, now = Date.now()): void {
    const run = this.db.transaction(() => {
      this.db.exec("UPDATE sessions SET active = 0 WHERE active = 1");
      const mark = this.db.prepare("UPDATE sessions SET active = 1, synced_at = ? WHERE id = ?");
      for (const id of ids) mark.run(now, id);
    });
    run();
  }

  markActive(id: string, active: boolean, now = Date.now()): void {
    this.db
      .prepare("UPDATE sessions SET active = ?, synced_at = ? WHERE id = ?")
      .run(active ? 1 : 0, now, id);
  }

  updateSessionUsage(id: string, cost: number | undefined, tokens: TokenUsage | undefined, now = Date.now()): void {
    if (cost === undefined && tokens === undefined) return;
    const row = this.db.query("SELECT cost, tokens FROM sessions WHERE id = ?").get(id) as Row | null;
    if (!row) return;
    this.db
      .prepare("UPDATE sessions SET cost = ?, tokens = ?, synced_at = ? WHERE id = ?")
      .run(
        cost ?? number(row.cost),
        tokens ? JSON.stringify(tokens) : String(row.tokens ?? "{}"),
        now,
        id,
      );
  }

  getSessions(query: SessionQuery = {}): Session[] {
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
    return (this.db.query(sql).all(...params) as Row[]).map(rowToSession);
  }

  getSession(id: string): Session | null {
    const row = this.db.query("SELECT * FROM sessions WHERE id = ?").get(id) as Row | null;
    return row ? rowToSession(row) : null;
  }

  // MARK: - Messages

  upsertMessages(sessionID: string, messages: SessionMessage[], now = Date.now()): void {
    const insert = this.db.prepare(`
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
    const directory = this.getSession(sessionID)?.location.directory;
    const run = this.db.transaction((items: SessionMessage[]) => {
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
        this.storeChanges(
          sessionID,
          message.id,
          message.content ?? [],
          number(message.time?.created),
          directory,
          now,
        );
        if (message.content) {
          this.storeToolCalls(
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
  private storeToolCalls(
    sessionID: string,
    messageID: string,
    parts: SessionMessage["content"],
    created: number,
    now: number,
  ): void {
    this.db
      .prepare("DELETE FROM tool_calls WHERE session_id = ? AND message_id = ?")
      .run(sessionID, messageID);

    const insert = this.db.prepare(`
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
  private storeChanges(
    sessionID: string,
    messageID: string,
    parts: SessionMessage["content"],
    created: number,
    directory: string | null | undefined,
    now: number,
  ): void {
    const insert = this.db.prepare(`
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

  getChanges(sessionID: string): FileDiff[] {
    const rows = this.db
      .query(
        `SELECT * FROM changes WHERE session_id = ?
         ORDER BY created DESC, part_id DESC, file ASC`,
      )
      .all(sessionID) as Row[];
    return rows.map((row) => this.rowToFileDiff(row));
  }

  /**
   * Changes across a project, newest first. Sessions are joined so the client
   * can group by session without a second request.
   */
  getProjectChanges(projectID: string, limit = 2_000): FileDiff[] {
    const capped = Math.min(Math.max(Math.floor(limit), 1), 5_000);
    const rows = this.db
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
      const diff = this.rowToFileDiff(row);
      const sessionID = text(row.session_id);
      if (sessionID) diff.sessionID = sessionID;
      const title = text(row.session_title);
      if (title) diff.sessionTitle = title;
      return diff;
    });
  }

  private rowToFileDiff(row: Row): FileDiff {
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

  getMessageSync(sessionID: string): MessageSync | null {
    const row = this.db
      .query("SELECT * FROM message_syncs WHERE session_id = ?")
      .get(sessionID) as Row | null;
    if (!row) return null;
    return {
      syncedAt: number(row.synced_at),
      oldestCursor: text(row.oldest_cursor) ?? null,
      complete: number(row.complete) === 1,
    };
  }

  putMessageSync(sessionID: string, sync: MessageSync): void {
    this.db
      .prepare(
        `INSERT INTO message_syncs (session_id, synced_at, oldest_cursor, complete)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(session_id) DO UPDATE SET
           synced_at = excluded.synced_at,
           oldest_cursor = excluded.oldest_cursor,
           complete = excluded.complete`,
      )
      .run(sessionID, sync.syncedAt, sync.oldestCursor, sync.complete ? 1 : 0);
  }

  /** Cached messages, newest first, paged with the hub's own cursor. */
  getMessages(sessionID: string, limit = 100, cursor?: string | null): MessagePage {
    const capped = Math.min(Math.max(Math.floor(limit), 1), 500);
    const decoded = cursor ? decodeMessageCursor(cursor) : null;
    const rows = decoded
      ? (this.db
          .query(
            `SELECT * FROM messages
             WHERE session_id = ? AND (created < ? OR (created = ? AND id < ?))
             ORDER BY created DESC, id DESC LIMIT ?`,
          )
          .all(sessionID, decoded.t, decoded.t, decoded.i, capped + 1) as Row[])
      : (this.db
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

  getMessageCount(sessionID: string): number {
    const row = this.db.query("SELECT COUNT(*) AS n FROM messages WHERE session_id = ?").get(sessionID) as Row;
    return number(row.n);
  }

  /**
   * Per-session stats from cached messages and indexed tool calls. Callers that
   * need complete numbers should hydrate the message history first.
   */
  getSessionStats(sessionID: string): SessionStats | null {
    const session = this.getSession(sessionID);
    if (!session) return null;

    const counts = this.db
      .query(
        `SELECT
           COUNT(*) AS total,
           SUM(CASE WHEN type IN ('user', 'synthetic') THEN 1 ELSE 0 END) AS prompts,
           SUM(CASE WHEN type NOT IN ('user', 'synthetic') THEN 1 ELSE 0 END) AS steps
         FROM messages WHERE session_id = ?`,
      )
      .get(sessionID) as Row;

    const children = this.db
      .query("SELECT COUNT(*) AS n FROM sessions WHERE parent_id = ?")
      .get(sessionID) as Row;

    const files = this.db
      .query(
        `SELECT
           COUNT(DISTINCT file) AS files,
           SUM(additions) AS additions,
           SUM(deletions) AS deletions
         FROM changes WHERE session_id = ?`,
      )
      .get(sessionID) as Row;

    const sync = this.getMessageSync(sessionID);
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
      tools: this.getSessionTools(sessionID),
      failures: this.getSessionFailures(sessionID),
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

  private getSessionTools(sessionID: string): ToolsSummary {
    const rows = this.db
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
    const durationRows = this.db
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

  private getSessionFailures(sessionID: string): ToolFailure[] {
    const rows = this.db
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

  // MARK: - Stats and usage

  putStats(scope: string, payload: Stats, now = Date.now()): void {
    this.db
      .prepare(
        `INSERT INTO stats (scope, payload, fetched_at) VALUES (?, ?, ?)
         ON CONFLICT(scope) DO UPDATE SET payload = excluded.payload, fetched_at = excluded.fetched_at`,
      )
      .run(scope, JSON.stringify(payload), now);
  }

  getStats(scope: string): CachedStats | null {
    const row = this.db.query("SELECT payload, fetched_at FROM stats WHERE scope = ?").get(scope) as Row | null;
    if (!row) return null;
    try {
      return { data: JSON.parse(String(row.payload)) as Stats, fetchedAt: number(row.fetched_at) };
    } catch {
      return null;
    }
  }

  putUsage(payload: GoUsage | null, fetchedAt: number | null, error: string | null, now = Date.now()): void {
    this.db
      .prepare(
        `INSERT INTO usage (id, payload, fetched_at, attempted_at, error) VALUES (1, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           payload = excluded.payload,
           fetched_at = excluded.fetched_at,
           attempted_at = excluded.attempted_at,
           error = excluded.error`,
      )
      .run(payload ? JSON.stringify(payload) : null, fetchedAt, now, error);
  }

  /** Records a failed attempt while keeping the last good payload. */
  putUsageError(error: string, now = Date.now()): void {
    this.db
      .prepare(
        `INSERT INTO usage (id, payload, fetched_at, attempted_at, error) VALUES (1, NULL, NULL, ?, ?)
         ON CONFLICT(id) DO UPDATE SET attempted_at = excluded.attempted_at, error = excluded.error`,
      )
      .run(now, error);
  }

  getUsage(): CachedUsage {
    const row = this.db.query("SELECT * FROM usage WHERE id = 1").get() as Row | null;
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

  counts(): { sessions: number; messages: number; projects: number } {
    const row = this.db
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
}
