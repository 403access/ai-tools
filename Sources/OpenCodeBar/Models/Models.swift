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

// MARK: - Session messages

/// Arbitrary JSON, used for tool inputs and metadata whose shape varies by tool.
enum JSONValue: Decodable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// A short one-line description for compact UI, e.g. a tool's command.
    var compactDescription: String {
        switch self {
        case .string(let value):
            return value.replacingOccurrences(of: "\n", with: " ")
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            return values.map(\.compactDescription).joined(separator: ", ")
        case .object(let values):
            let pairs = values.keys.sorted().map { "\($0): \(values[$0]!.compactDescription)" }
            return pairs.joined(separator: ", ")
        }
    }

    /// Multi-line JSON-ish rendering for expanded tool details.
    func prettyString(indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent)
        let childPad = String(repeating: " ", count: indent + 2)
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value == value.rounded() ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            return values
                .map { childPad + $0.prettyString(indent: indent + 2) }
                .joined(separator: ",\n")
                .wrapped(in: "[\n", "\(pad)]")
        case .object(let values):
            guard !values.isEmpty else { return "{}" }
            return values.keys.sorted()
                .map { "\(childPad)\($0): \(values[$0]!.prettyString(indent: indent + 2))" }
                .joined(separator: ",\n")
                .wrapped(in: "{\n", "\(pad)}")
        }
    }
}

private extension String {
    func wrapped(in prefix: String, _ suffix: String) -> String {
        prefix + self + suffix
    }
}

struct SessionMessagesResponse: Decodable {
    var data: [SessionMessage]
    var cursor: Cursor?

    struct Cursor: Decodable {
        var previous: String?
        var next: String?
    }
}

struct SessionMessage: Decodable, Identifiable {
    var id: String
    var type: String
    var time: Time
    var text: String?
    var content: [MessagePart]?
    var model: ModelRef?
    var agent: String?
    var cost: Double?
    var tokens: TokenUsage?

    struct Time: Decodable {
        var created: Double
        var streamed: Double?
        var completed: Double?

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
    }

    var isUserLike: Bool { type == "user" || type == "synthetic" }
    var isSynthetic: Bool { type == "synthetic" }
    var roleLabel: String {
        switch type {
        case "user": return "You"
        case "synthetic": return "System"
        default: return "Assistant"
        }
    }

    /// User prompts store their text at the top level.
    var promptText: String? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

struct MessagePart: Decodable {
    var type: String
    var id: String?
    var text: String?
    var name: String?
    var state: ToolState?
    var time: Time?

    struct Time: Decodable {
        var created: Double?
        var ran: Double?
        var completed: Double?
    }

    struct ToolState: Decodable {
        var status: String?
        var input: JSONValue?
        var content: [MessagePart]?
        var metadata: JSONValue?

        /// Tool output is usually delivered as text parts.
        var outputText: String? {
            let text = (content ?? []).compactMap(\.text).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
            guard let metadata else { return nil }
            let fallback = metadata.compactDescription
            return fallback.isEmpty ? nil : fallback
        }

        var inputSummary: String? {
            guard let input else { return nil }
            if case .object(let values) = input {
                for key in ["command", "description", "filePath", "path", "pattern", "query", "url", "prompt"] {
                    if let value = values[key]?.stringValue, !value.isEmpty {
                        return value.replacingOccurrences(of: "\n", with: " ")
                    }
                }
            }
            let summary = input.compactDescription
            return summary.isEmpty ? nil : summary
        }
    }
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
