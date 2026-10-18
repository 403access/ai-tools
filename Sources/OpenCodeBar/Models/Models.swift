import Foundation

// MARK: - Token usage

struct TokenUsage: Codable, Hashable, Sendable {
    var input: Double
    var output: Double
    var reasoning: Double
    var cache: Cache

    struct Cache: Codable, Hashable, Sendable {
        var read: Double
        var write: Double
    }

    static let zero = TokenUsage(input: 0, output: 0, reasoning: 0, cache: .init(read: 0, write: 0))

    /// Tokens generated/consumed by the model itself (excludes cache traffic).
    var generated: Double { input + output + reasoning }
    /// Everything, including cache reads and writes.
    var total: Double { generated + cache.read + cache.write }
}

// MARK: - Model reference

struct ModelRef: Codable, Hashable, Sendable {
    var id: String
    var providerID: String
    var variant: String?

    var label: String {
        if let variant, variant != "default" {
            return "\(id) · \(variant)"
        }
        return id
    }
}

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
    var location: Location

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
    var directory: String? { location.directory }
    var displayTitle: String {
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Untitled session" : t
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
    }

    var displayName: String {
        if let name, !name.isEmpty { return name }
        return URL(fileURLWithPath: canonical).lastPathComponent
    }
}

// MARK: - Aggregate statistics

struct Stats: Codable, Hashable, Sendable {
    var range: Range
    var sessions: Int
    var subagents: Int
    var prompts: Int
    var steps: Int
    var tokens: TokenUsage
    var cost: Double
    var tools: Tools
    var activeDays: Int
    var streak: Int
    var activity: [Activity]
    var models: [ModelUsage]

    struct Range: Codable, Hashable, Sendable {
        var from: Double
        var to: Double
    }

    struct Activity: Codable, Hashable, Sendable, Identifiable {
        var date: String
        var steps: Int
        var id: String { date }
    }

    struct ModelUsage: Codable, Hashable, Sendable, Identifiable {
        var model: ModelRef
        var steps: Int
        var tokens: TokenUsage
        var cost: Double
        var id: String { "\(model.providerID)/\(model.id)" }
    }

    struct Tools: Codable, Hashable, Sendable {
        var mode: String
        var totals: ToolTotals?
    }

    struct ToolTotals: Codable, Hashable, Sendable {
        var calls: Int
        var succeeded: Int
        var failed: Int
        var unfinished: Int
    }

    func steps(onDay day: String) -> Int {
        activity.first { $0.date == day }?.steps ?? 0
    }

    var maxSteps: Int { activity.map(\.steps).max() ?? 0 }
}

// MARK: - API envelopes

struct SessionsResponse: Decodable {
    var data: [Session]
    var cursor: Cursor?

    struct Cursor: Decodable {
        var previous: String?
        var next: String?
    }
}

struct ActiveSessionsResponse: Decodable {
    var data: [String: ActiveState]

    struct ActiveState: Decodable {
        var type: String
    }
}

struct StatsResponse: Decodable {
    var data: Stats
}

struct SessionEnvelope: Decodable {
    var data: Session
}

struct ServerInfo: Decodable {
    var version: String?
    var pid: Int?
    var urls: [String]?
    var capabilities: Capabilities?

    struct Capabilities: Decodable {
        var persistentPty: Bool?
    }
}
