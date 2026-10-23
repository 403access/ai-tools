import Foundation

extension MobileDatabase {
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
}
