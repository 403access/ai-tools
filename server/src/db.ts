import { Database } from "bun:sqlite";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import {
  ZERO_TOKENS,
  type GoUsage,
  type MessageCursor,
  type MessagesResponse,
  type Project,
  type Session,
  type SessionMessage,
  type Stats,
  type TokenUsage,
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
    if (version >= 1) return;

    this.db.exec(`
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
  }

  close(): void {
    this.db.close();
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
      }
    });
    run(messages);
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
