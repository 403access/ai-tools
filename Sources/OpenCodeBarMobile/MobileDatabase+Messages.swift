import Foundation
import SQLite3

extension MobileDatabase {
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
}
