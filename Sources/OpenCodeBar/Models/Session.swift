import Foundation

// MARK: - Session

struct Session: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var parentID: String?
    var projectID: String
    var agent: String?
    var model: ModelRef?
    var cost: Double
    var tokens: TokenUsage
    var outcome: String?
    var time: Time
    var title: String?
    var subpath: String?
    /// Present when OpenCode created this session as a fork of another one.
    var fork: Fork? = nil
    var location: Location

    /// The source conversation a fork was copied from.
    struct Fork: Codable, Hashable, Sendable {
        var sessionID: String
        var boundary: Boundary?

        /// Where the fork was cut in the source conversation.
        struct Boundary: Codable, Hashable, Sendable {
            var type: String?
            var messageID: String?
        }
    }

    struct Time: Codable, Hashable, Sendable {
        var created: Double
        var updated: Double
        var idle: Double?
        var viewed: Double?
        var archived: Double?

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
        var updatedDate: Date { Date(timeIntervalSince1970: updated / 1000) }
    }

    struct Location: Codable, Hashable, Sendable {
        var directory: String?
    }

    var isSubagent: Bool { parentID != nil }
    var isFork: Bool { fork != nil }
    var directory: String? { location.directory }
    var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled session" : t
    }

    /// Human-readable terminal state for a session that is no longer running.
    var outcomeLabel: String {
        switch outcome {
        case "failed": return "Failed"
        case "interrupted": return "Interrupted"
        default: return "Finished"
        }
    }

    var hasFailureOutcome: Bool {
        outcome == "failed" || outcome == "interrupted"
    }
}

// MARK: - Project

struct Project: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var canonical: String
    var vcs: String?
    var name: String?
    var time: Time
    var sandboxes: [String]

    struct Time: Codable, Hashable, Sendable {
        var created: Double
        var updated: Double
        var active: Double?

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
        var updatedDate: Date { Date(timeIntervalSince1970: updated / 1000) }
        var activeDate: Date? { active.map { Date(timeIntervalSince1970: $0 / 1000) } }
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        let leaf = URL(fileURLWithPath: canonical).lastPathComponent
        if !leaf.isEmpty { return leaf }
        return canonical.isEmpty ? "Unknown project" : canonical
    }

    /// Most recent activity we know about for this project.
    var lastActiveDate: Date { time.activeDate ?? time.updatedDate }
}
