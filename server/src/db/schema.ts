import type { Database } from "bun:sqlite";
import { backfillToolCalls } from "./messages.ts";
import { number, type Row } from "./rows.ts";

const SCHEMA_VERSION = 10;

export function migrate(db: Database): void {
  const version = number((db.query("PRAGMA user_version").get() as Row | null)?.user_version);
  if (version >= SCHEMA_VERSION) return;

  if (version < 1) {
    db.exec(`
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

  if (version < 2) {
    db.exec(`
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
  }

  if (version < 3) {
    db.exec(`
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
    backfillToolCalls(db);
    db.exec("PRAGMA user_version = 3;");
  }

  if (version < 4) {
    db.exec(`
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
    db.exec("PRAGMA user_version = 4;");
  }

  if (version < 5) {
    db.exec(`
      CREATE TABLE IF NOT EXISTS sync_log (
        rev INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      );

      CREATE INDEX IF NOT EXISTS sync_log_kind_rev ON sync_log(kind, rev);
    `);
    db.exec("PRAGMA user_version = 5;");
  }

  if (version < 6) {
    // Message-level failures live on assistant and idle messages. Cache them
    // so the apps can explain a failed turn without re-reading OpenCode.
    for (const column of ["outcome", "finish", "error", "retry"]) {
      try {
        db.exec(`ALTER TABLE messages ADD COLUMN ${column} TEXT;`);
      } catch {
        // A partially applied migration may already have added this column.
      }
    }
    // Older cached rows have no failure details. Force one refresh of the
    // newest page per session so existing failures become visible.
    db.exec("DELETE FROM message_syncs;");
    db.exec("PRAGMA user_version = 6;");
  }

  if (version < 7) {
    // OpenCode marks a forked session with its source conversation. Cache the
    // relationship so both apps can explain a fork and list a session's forks.
    for (const column of ["fork_session_id TEXT", "fork_boundary TEXT"]) {
      try {
        db.exec(`ALTER TABLE sessions ADD COLUMN ${column};`);
      } catch {
        // A partially applied migration may already have added this column.
      }
    }
    db.exec(`
      CREATE INDEX IF NOT EXISTS sessions_fork_source
        ON sessions(fork_session_id, updated DESC);
    `);
    db.exec("PRAGMA user_version = 7;");
  }

  if (version < 8) {
    // Task-board state lives on the session row so it rides the existing sync
    // feed to every device. Labels are derived on read; only the raw signals
    // (and the user's resolution) need to be stored.
    for (const column of [
      "task_created REAL",
      "task_status TEXT",
      "task_done_at REAL",
      "task_context TEXT",
    ]) {
      try {
        db.exec(`ALTER TABLE sessions ADD COLUMN ${column};`);
      } catch {
        // A partially applied migration may already have added this column.
      }
    }
    db.exec(`
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS sessions_task
        ON sessions(task_created, updated DESC);
    `);

    const now = Date.now();
    db.prepare("INSERT OR IGNORE INTO meta (key, value) VALUES ('task_epoch', ?)").run(String(now));
    // Give the board sensible content on first launch instead of an empty
    // tab: adopt running sessions and anything active in the last three days.
    // Older history stays out of the board.
    db.prepare(
      `UPDATE sessions
       SET task_created = updated, task_status = 'open'
       WHERE task_created IS NULL
         AND parent_id IS NULL
         AND (active = 1 OR updated >= ?)`,
    ).run(now - 3 * 24 * 60 * 60 * 1000);
    db.exec("PRAGMA user_version = 8;");
  }

  if (version < 9) {
    // Pause/stop are local to the hub: OpenCode can interrupt a turn, but it
    // does not know that the user wants it held until a later time. Keeping
    // the state on the session row lets it ride the existing sync feed and
    // survive a hub restart.
    for (const column of [
      "paused_at REAL",
      "paused_until REAL",
      "stopped_at REAL",
    ]) {
      try {
        db.exec(`ALTER TABLE sessions ADD COLUMN ${column};`);
      } catch {
        // A partially applied migration may already have added this column.
      }
    }
    db.exec(`
      CREATE INDEX IF NOT EXISTS sessions_paused_until
        ON sessions(paused_until)
        WHERE paused_until IS NOT NULL;
    `);
    db.exec("PRAGMA user_version = 9;");
  }

  if (version < 10) {
    // A queued task is a session the hub has not prompted yet. The first
    // prompt is stored until a concurrency slot frees (or the requested start
    // time passes), then sent by the fast loop.
    for (const column of [
      "queued_at REAL",
      "queued_until REAL",
      "queued_prompt TEXT",
    ]) {
      try {
        db.exec(`ALTER TABLE sessions ADD COLUMN ${column};`);
      } catch {
        // A partially applied migration may already have added this column.
      }
    }
    db.exec(`
      CREATE INDEX IF NOT EXISTS sessions_queued
        ON sessions(queued_at)
        WHERE queued_at IS NOT NULL;
      PRAGMA user_version = 10;
    `);
  }
}
