import Foundation

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
        var usage: [ToolUsage]?
    }

    struct ToolTotals: Codable, Hashable, Sendable {
        var calls: Int
        var succeeded: Int
        var failed: Int
        var unfinished: Int

        static let zero = ToolTotals(calls: 0, succeeded: 0, failed: 0, unfinished: 0)

        var successRate: Double? {
            guard calls > 0 else { return nil }
            return Double(succeeded) / Double(calls)
        }
    }

    /// Per-tool reliability from the stats API's detail mode.
    struct ToolUsage: Codable, Hashable, Sendable, Identifiable {
        var name: String
        var calls: Int
        var succeeded: Int
        var failed: Int
        var unfinished: Int
        var durationP50: Double?

        var id: String { name }

        var successRate: Double? {
            guard calls > 0 else { return nil }
            return Double(succeeded) / Double(calls)
        }
    }

    func steps(onDay day: String) -> Int {
        activity.first { $0.date == day }?.steps ?? 0
    }

    var maxSteps: Int { activity.map(\.steps).max() ?? 0 }
}

// MARK: - Per-session statistics

/// Stats derived by the hub from a session's cached messages and tool calls.
struct SessionStats: Decodable, Hashable, Sendable {
    var sessionID: String
    var prompts: Int
    var steps: Int
    var subagents: Int
    var messages: Int
    var tokens: TokenUsage
    var cost: Double
    var tools: Stats.Tools
    var failures: [ToolFailure]
    var files: Files
    var time: Time
    /// False when only part of the session history has been cached.
    var complete: Bool

    var totals: Stats.ToolTotals { tools.totals ?? .zero }

    struct ToolFailure: Decodable, Hashable, Sendable, Identifiable {
        var name: String
        var error: String?
        var messageID: String?
        var partID: String?
        var created: Double

        var id: String { "\(partID ?? messageID ?? name)-\(Int(created))" }
        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
        var message: String { error?.isEmpty == false ? error! : "Tool call failed" }
    }

    struct Files: Decodable, Hashable, Sendable {
        var files: Int
        var additions: Int
        var deletions: Int
        var net: Int { additions - deletions }
    }

    struct Time: Decodable, Hashable, Sendable {
        var created: Double
        var updated: Double
        /// Wall-clock duration in milliseconds.
        var duration: Double
        var idle: Double?

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
        var updatedDate: Date { Date(timeIntervalSince1970: updated / 1000) }
    }
}

struct SessionStatsResponse: Decodable {
    var data: SessionStats
}
