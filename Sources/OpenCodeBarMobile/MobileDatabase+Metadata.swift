import Foundation

extension MobileDatabase {
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
}
