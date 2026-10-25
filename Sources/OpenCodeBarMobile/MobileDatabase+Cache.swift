import Foundation
import SQLite3

/// A row from the generic on-demand cache. `data` is nil for a cached miss
/// (for example an app that has no icon).
struct CachedBlob {
    let data: Data?
    let fetchedAt: Date
}

extension MobileDatabase {
    /// Reads an on-demand payload. Returns nil when the key has never been
    /// fetched; a cached miss comes back as `data == nil`.
    func cachedBlob(kind: String, key: String) -> CachedBlob? {
        lock.lock()
        defer { lock.unlock() }

        guard let statement = try? prepare(
            "SELECT payload, fetched_at FROM cache WHERE kind = ? AND key = ?"
        ) else { return nil }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, kind)
        bindText(statement, 2, key)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }

        let fetchedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
        if sqlite3_column_type(statement, 0) == SQLITE_NULL {
            return CachedBlob(data: nil, fetchedAt: fetchedAt)
        }

        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else {
            return CachedBlob(data: Data(), fetchedAt: fetchedAt)
        }
        return CachedBlob(data: Data(bytes: bytes, count: count), fetchedAt: fetchedAt)
    }

    func storeBlob(
        kind: String,
        key: String,
        data: Data?,
        fetchedAt: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard let statement = try? prepare(
            """
            INSERT INTO cache (kind, key, payload, fetched_at) VALUES (?, ?, ?, ?)
            ON CONFLICT(kind, key) DO UPDATE SET
              payload = excluded.payload,
              fetched_at = excluded.fetched_at
            """
        ) else { return }
        defer { sqlite3_finalize(statement) }

        bindText(statement, 1, kind)
        bindText(statement, 2, key)
        if let data {
            _ = data.withUnsafeBytes { buffer in
                sqlite3_bind_blob(
                    statement,
                    3,
                    buffer.baseAddress,
                    Int32(buffer.count),
                    cacheTransient
                )
            }
        } else {
            sqlite3_bind_null(statement, 3)
        }
        sqlite3_bind_double(statement, 4, fetchedAt.timeIntervalSince1970)
        _ = sqlite3_step(statement)
    }

    func removeCachedBlobs(kind: String) {
        lock.lock()
        defer { lock.unlock() }
        try? execute("DELETE FROM cache WHERE kind = ?", bind: [kind])
    }

    // MARK: - System snapshot

    func cachedSystemInfo() -> (info: SystemInfo, fetchedAt: Date)? {
        guard let row = cachedBlob(kind: "system-info", key: "current"),
              let data = row.data,
              let envelope = try? Self.decoder.decode(SystemInfoEnvelope.self, from: data)
        else { return nil }
        return (envelope.data, row.fetchedAt)
    }

    func storeSystemInfoPayload(_ payload: Data, fetchedAt: Date = Date()) {
        storeBlob(kind: "system-info", key: "current", data: payload, fetchedAt: fetchedAt)
    }
}

extension MobileDatabase: AppIconCacheStore {
    func cachedIcon(for key: String) -> CachedAppIcon? {
        guard let row = cachedBlob(kind: "app-icon", key: key) else { return nil }
        return CachedAppIcon(data: row.data, fetchedAt: row.fetchedAt)
    }

    func storeCachedIcon(_ data: Data?, for key: String, fetchedAt: Date) {
        storeBlob(kind: "app-icon", key: key, data: data, fetchedAt: fetchedAt)
    }
}

private let cacheTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
