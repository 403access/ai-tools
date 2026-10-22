import Foundation
import SQLite3

/// Local SQLite cache for the iOS app.
///
/// The store renders from here first, then catches up with the hub through
/// `GET /api/sync?since=…`. Sessions, projects, messages, stats and usage are
/// kept as JSON blobs so the wire models stay the single source of truth.
final class MobileDatabase {
    struct Snapshot {
        var sessions: [Session] = []
        var projects: [Project] = []
        var stats: Stats?
        var usage: HubUsageResponse?
        var revision = 0
        var lastSyncedAt: Date?
        var active: [String] = []
        var activeAt: Date?
    }

    /// Newest cached messages kept per session. Older pages still come from the
    /// hub's cursor when the user scrolls back.
    private static let messageRetention = 500

    private var handle: OpaquePointer?
    private let lock = NSLock()
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    /// Opens (and migrates) the cache. Returns nil when the database cannot be
    /// created; the app then simply works without offline data.
    init?(filename: String = "opencodebar.sqlite") {
        guard let directory = Self.supportDirectory() else { return nil }
        let path = directory.appendingPathComponent(filename).path

        guard sqlite3_open_v2(
            path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            handle = nil
            return nil
        }

        sqlite3_busy_timeout(handle, 5_000)
        do {
            try execRaw("PRAGMA journal_mode = WAL;")
            try execRaw("PRAGMA synchronous = NORMAL;")
            try migrate()
        } catch {
            sqlite3_close(handle)
            self.handle = nil
            return nil
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    // MARK: - Snapshot

    func loadSnapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }

        var snapshot = Snapshot()
        snapshot.sessions = decodeRows("SELECT payload FROM sessions ORDER BY updated DESC")
        snapshot.projects = decodeRows("SELECT payload FROM projects ORDER BY updated DESC")
        snapshot.revision = Int(meta("revision") ?? "0") ?? 0
        if let value = meta("lastSyncedAt") {
            snapshot.lastSyncedAt = Date(timeIntervalSince1970: Double(value) ?? 0)
        }
        if let value = meta("active"), let data = value.data(using: .utf8) {
            snapshot.active = (try? Self.decoder.decode([String].self, from: data)) ?? []
        }
        if let value = meta("activeAt") {
            snapshot.activeAt = Date(timeIntervalSince1970: Double(value) ?? 0)
        }
        if let row = firstRow("SELECT payload FROM stats WHERE scope = ?", bind: ["__global__"]) {
            snapshot.stats = decode(row)
        }
        if let row = firstRow("SELECT payload FROM usage WHERE id = 1", bind: []) {
            snapshot.usage = decode(row)
        }
        return snapshot
    }

    // MARK: - Sessions and projects

    func replaceSessions(_ sessions: [Session]) {
        lock.lock()
        defer { lock.unlock() }
        try? transaction {
            try execute("DELETE FROM sessions")
            try writeSessions(sessions)
        }
    }

    func upsertSessions(_ sessions: [Session]) {
        guard !sessions.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        try? transaction { try writeSessions(sessions) }
    }

    func deleteSessions(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        try? transaction {
            for id in ids {
                try execute("DELETE FROM sessions WHERE id = ?", bind: [id])
            }
        }
    }

    func replaceProjects(_ projects: [Project]) {
        lock.lock()
        defer { lock.unlock() }
        try? transaction {
            try execute("DELETE FROM projects")
            try writeProjects(projects)
        }
    }

    func upsertProjects(_ projects: [Project]) {
        guard !projects.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        try? transaction { try writeProjects(projects) }
    }

    func deleteProjects(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        try? transaction {
            for id in ids {
                try execute("DELETE FROM projects WHERE id = ?", bind: [id])
            }
        }
    }

    func setRevision(_ revision: Int, syncedAt: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        try? transaction {
            try setMeta("revision", String(revision))
            try setMeta("lastSyncedAt", String(syncedAt.timeIntervalSince1970))
        }
    }

    func setActive(_ ids: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(ids),
              let value = String(data: data, encoding: .utf8)
        else { return }
        try? transaction {
            try setMeta("active", value)
            try setMeta("activeAt", String(Date().timeIntervalSince1970))
        }
    }

    // MARK: - Messages

    func messages(for sessionID: String, limit: Int = 100) -> [SessionMessage] {
        lock.lock()
        defer { lock.unlock() }
        let rows = rows(
            "SELECT payload FROM messages WHERE session_id = ? ORDER BY created DESC, id DESC LIMIT \(max(1, limit))",
            bind: [sessionID]
        )
        return rows.compactMap { decode($0) as SessionMessage? }
    }

    func upsertMessages(_ messages: [SessionMessage], for sessionID: String) {
        guard !messages.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        try? transaction {
            let statement = try prepare(
                """
                INSERT INTO messages (session_id, id, created, payload)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(session_id, id) DO UPDATE SET
                  created = excluded.created,
                  payload = excluded.payload
                """
            )
            defer { sqlite3_finalize(statement) }
            for message in messages {
                guard let payload = encode(message) else { continue }
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bindText(statement, 1, sessionID)
                bindText(statement, 2, message.id)
                sqlite3_bind_double(statement, 3, message.time.created)
                bindText(statement, 4, payload)
                try step(statement)
            }
            try execute(
                """
                DELETE FROM messages WHERE session_id = ? AND id NOT IN (
                  SELECT id FROM messages WHERE session_id = ? ORDER BY created DESC LIMIT \(Self.messageRetention)
                )
                """,
                bind: [sessionID, sessionID]
            )
        }
    }

    // MARK: - Stats and usage

    func putStats(_ stats: Stats, fetchedAt: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = encode(stats) else { return }
        try? transaction {
            try execute(
                """
                INSERT INTO stats (scope, payload, fetched_at) VALUES (?, ?, ?)
                ON CONFLICT(scope) DO UPDATE SET
                  payload = excluded.payload,
                  fetched_at = excluded.fetched_at
                """,
                bind: ["__global__", payload, String(fetchedAt.timeIntervalSince1970)]
            )
        }
    }

    func putUsage(_ usage: HubUsageResponse) {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = encode(usage) else { return }
        try? transaction {
            try execute(
                """
                INSERT INTO usage (id, payload, fetched_at) VALUES (1, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  payload = excluded.payload,
                  fetched_at = excluded.fetched_at
                """,
                bind: [payload, String(Date().timeIntervalSince1970)]
            )
        }
    }

    // MARK: - Hub identity / clearing

    /// True when the cache was written for another hub. Pairing a different
    /// server must not mix its sessions into this one.
    func matches(hubURL: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return meta("hubURL") == hubURL
    }

    func setHubURL(_ url: String) {
        lock.lock()
        defer { lock.unlock() }
        try? transaction { try setMeta("hubURL", url) }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? transaction {
            try execute("DELETE FROM sessions")
            try execute("DELETE FROM projects")
            try execute("DELETE FROM messages")
            try execute("DELETE FROM stats")
            try execute("DELETE FROM usage")
            try execute("DELETE FROM meta WHERE key NOT IN ('hubURL', 'schemaVersion')")
        }
    }

    // MARK: - Schema

    private func migrate() throws {
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

    // MARK: - Write helpers

    private func writeSessions(_ sessions: [Session]) throws {
        let statement = try prepare(
            """
            INSERT INTO sessions (id, payload, updated) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              payload = excluded.payload,
              updated = excluded.updated
            """
        )
        defer { sqlite3_finalize(statement) }
        for session in sessions {
            guard let payload = encode(session) else { continue }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, 1, session.id)
            bindText(statement, 2, payload)
            sqlite3_bind_double(statement, 3, session.time.updated)
            try step(statement)
        }
    }

    private func writeProjects(_ projects: [Project]) throws {
        let statement = try prepare(
            """
            INSERT INTO projects (id, payload, updated) VALUES (?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              payload = excluded.payload,
              updated = excluded.updated
            """
        )
        defer { sqlite3_finalize(statement) }
        for project in projects {
            guard let payload = encode(project) else { continue }
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bindText(statement, 1, project.id)
            bindText(statement, 2, payload)
            sqlite3_bind_double(statement, 3, project.time.updated)
            try step(statement)
        }
    }

    // MARK: - SQLite plumbing

    private static func supportDirectory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = base.appendingPathComponent("OpenCodeBar", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func meta(_ key: String) -> String? {
        firstRow("SELECT value FROM meta WHERE key = ?", bind: [key])
    }

    private func setMeta(_ key: String, _ value: String) throws {
        try execute(
            """
            INSERT INTO meta (key, value) VALUES (?, ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
            """,
            bind: [key, value]
        )
    }

    private func decode<T: Decodable>(_ payload: String) -> T? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? Self.decoder.decode(T.self, from: data)
    }

    private func decodeRows<T: Decodable>(_ sql: String) -> [T] {
        rows(sql, bind: []).compactMap { decode($0) as T? }
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? Self.encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func execRaw(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? errorText
            sqlite3_free(message)
            throw DatabaseError.message(text)
        }
    }

    private func execute(_ sql: String, bind: [String] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bind.enumerated() {
            bindText(statement, Int32(offset + 1), value)
        }
        try step(statement)
    }

    private func firstRow(_ sql: String, bind: [String]) -> String? {
        rows(sql, bind: bind, limit: 1).first
    }

    private func rows(_ sql: String, bind: [String], limit: Int? = nil) -> [String] {
        guard let statement = try? prepare(sql) else { return [] }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in bind.enumerated() {
            self.bindText(statement, Int32(offset + 1), value)
        }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                result.append(String(cString: text))
            }
            if let limit, result.count >= limit { break }
        }
        return result
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw DatabaseError.message(errorText)
        }
        return statement
    }

    private func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func step(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw DatabaseError.message(errorText)
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private var errorText: String {
        guard let handle, let message = sqlite3_errmsg(handle) else { return "SQLite error" }
        return String(cString: message)
    }

    private enum DatabaseError: Error {
        case message(String)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
