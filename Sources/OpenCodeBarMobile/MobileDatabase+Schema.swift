import Foundation

extension MobileDatabase {
    // MARK: - Schema

    func migrate() throws {
        let version = Int(meta("schemaVersion") ?? "0") ?? 0
        guard version < 1 else { return }

        try execRaw(
            """
            CREATE TABLE IF NOT EXISTS meta (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sessions (
              id TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              updated REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS sessions_updated ON sessions(updated DESC);

            CREATE TABLE IF NOT EXISTS projects (
              id TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              updated REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS messages (
              session_id TEXT NOT NULL,
              id TEXT NOT NULL,
              created REAL NOT NULL,
              payload TEXT NOT NULL,
              PRIMARY KEY (session_id, id)
            );
            CREATE INDEX IF NOT EXISTS messages_session_created
              ON messages(session_id, created DESC);

            CREATE TABLE IF NOT EXISTS stats (
              scope TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              fetched_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS usage (
              id INTEGER PRIMARY KEY CHECK (id = 1),
              payload TEXT NOT NULL,
              fetched_at REAL NOT NULL
            );
            """
        )
        try transaction { try setMeta("schemaVersion", "1") }
    }
}
