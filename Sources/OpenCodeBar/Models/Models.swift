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

// MARK: - Session messages

/// Arbitrary JSON, used for tool inputs and metadata whose shape varies by tool.
enum JSONValue: Decodable, Hashable, Sendable {
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

struct SessionMessage: Decodable, Identifiable, Equatable {
    var id: String
    var type: String
    var time: Time
    var text: String?
    var content: [MessagePart]?
    var model: ModelRef?
    var agent: String?
    var cost: Double?
    var tokens: TokenUsage?

    struct Time: Decodable, Equatable {
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

    /// File patches carried by this message's tool calls.
    var fileChanges: [FileChange] {
        (content ?? []).flatMap(\.fileChanges)
    }
}

extension MessagePart {
    /// Exact patches from edit metadata; for `write` calls, synthesize the
    /// added content so the conversation shows what was written.
    var fileChanges: [FileChange] {
        let recorded = state?.fileChanges ?? []
        if !recorded.isEmpty { return recorded }

        guard (name ?? "").lowercased() == "write",
              case .object(let input)? = state?.input,
              let path = input["path"]?.stringValue ?? input["filePath"]?.stringValue,
              let content = input["content"]?.stringValue
        else { return [] }

        var lines = content.components(separatedBy: "\n")
        if lines.count > 1, lines.last == "" { lines.removeLast() }
        let patch = (
            ["--- /dev/null", "+++ b/\(path)", "@@ -0,0 +1,\(lines.count) @@"]
                + lines.map { "+\($0)" }
        ).joined(separator: "\n")

        return [
            FileChange(
                file: path,
                patch: patch,
                additions: lines.count,
                deletions: 0,
                status: "added",
                sessionID: nil,
                sessionTitle: nil,
                messageID: nil,
                created: nil
            )
        ]
    }
}

/// One file changed by a tool call, with the patch OpenCode recorded. Session
/// endpoints only include the first five fields; project aggregation adds the
/// session context.
struct FileChange: Decodable, Identifiable, Hashable, Sendable {
    var file: String?
    var patch: String?
    var additions: Int
    var deletions: Int
    var status: String?
    var sessionID: String?
    var sessionTitle: String?
    var messageID: String?
    var created: Double?

    var id: String {
        [
            sessionID ?? "",
            messageID ?? "",
            file ?? "",
            created.map { String(Int($0)) } ?? "",
            String(patch?.hashValue ?? 0),
        ].joined(separator: "|")
    }

    var displayPath: String { file ?? "Unknown file" }

    var statusLabel: String {
        switch status {
        case "added": return "added"
        case "deleted": return "deleted"
        case "modified": return "modified"
        default: return "changed"
        }
    }

    var statusIcon: String {
        switch status {
        case "added": return "plus.circle.fill"
        case "deleted": return "minus.circle.fill"
        default: return "pencil.circle.fill"
        }
    }

    var patchLines: [String] {
        guard let patch, !patch.isEmpty else { return [] }
        return patch
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let text = String(line)
                return text.hasSuffix("\r") ? String(text.dropLast()) : text
            }
    }
}

struct ChangesResponse: Decodable {
    var data: [FileChange]
}

// MARK: - Project files

/// One file in a project directory. `status` comes from git's working tree, so
/// unchanged files only have a path.
struct ProjectFile: Decodable, Identifiable, Hashable, Sendable {
    var path: String
    var status: String?

    var id: String { path }
    var isChanged: Bool { status != nil }

    var name: String {
        (path as NSString).lastPathComponent
    }

    /// Everything before the file name, with a trailing slash. Empty at the root.
    var directory: String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "" : parent + "/"
    }

    var statusLabel: String {
        switch status {
        case "added": return "Added"
        case "modified": return "Modified"
        case "deleted": return "Deleted"
        case "renamed": return "Renamed"
        default: return "Changed"
        }
    }

    var statusIcon: String {
        switch status {
        case "added": return "plus.circle.fill"
        case "modified": return "pencil.circle.fill"
        case "deleted": return "minus.circle.fill"
        case "renamed": return "arrow.triangle.2.circlepath.circle.fill"
        case nil: return "doc.text"
        default: return "circle.fill"
        }
    }
}

struct ProjectFiles: Decodable, Hashable, Sendable {
    var files: [ProjectFile]
    var vcs: String?
    var changed: Int
    var total: Int
    var truncated: Bool
}

struct ProjectFilesResponse: Decodable {
    var data: ProjectFiles
}

/// Groups repeated edits to the same file for the session/project summaries.
struct FileChangeGroup: Identifiable {
    var path: String
    var changes: [FileChange]

    var id: String { path }
    var additions: Int { changes.reduce(0) { $0 + $1.additions } }
    var deletions: Int { changes.reduce(0) { $0 + $1.deletions } }
    var edits: Int { changes.count }

    static func grouped(_ changes: [FileChange]) -> [FileChangeGroup] {
        var order: [String] = []
        var groups: [String: [FileChange]] = [:]
        for change in changes {
            let path = change.displayPath
            if groups[path] == nil { order.append(path) }
            groups[path, default: []].append(change)
        }
        return order.map { path in
            let changes = (groups[path] ?? []).sorted { lhs, rhs in
                let left = lhs.created ?? 0
                let right = rhs.created ?? 0
                if left != right { return left > right }
                return lhs.id < rhs.id
            }
            return FileChangeGroup(path: path, changes: changes)
        }
        .sorted { lhs, rhs in
            let left = lhs.changes.first?.created ?? 0
            let right = rhs.changes.first?.created ?? 0
            if left != right { return left > right }
            return lhs.path < rhs.path
        }
    }
}

struct MessagePart: Decodable, Equatable {
    var type: String
    var id: String?
    var text: String?
    var name: String?
    var state: ToolState?
    var time: Time?

    struct Time: Decodable, Equatable {
        var created: Double?
        var ran: Double?
        var completed: Double?
    }

    struct ToolState: Decodable, Equatable {
        var status: String?
        var input: JSONValue?
        var content: [MessagePart]?
        var metadata: JSONValue?
        var error: JSONValue?

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

        /// Patches OpenCode stores on edit/write tool calls. This is the same
        /// data the hub caches and aggregates for project changes.
        var fileChanges: [FileChange] {
            guard case .object(let metadata)? = metadata,
                  case .array(let files)? = metadata["files"]
            else { return [] }

            return files.compactMap { entry in
                guard case .object(let fields) = entry else { return nil }
                let file = fields["file"]?.stringValue
                let patch = fields["patch"]?.stringValue
                guard file != nil || patch != nil else { return nil }
                return FileChange(
                    file: file,
                    patch: patch,
                    additions: Self.integer(fields["additions"]),
                    deletions: Self.integer(fields["deletions"]),
                    status: fields["status"]?.stringValue,
                    sessionID: nil,
                    sessionTitle: nil,
                    messageID: nil,
                    created: nil
                )
            }
        }

        private static func integer(_ value: JSONValue?) -> Int {
            if case .number(let number) = value { return Int(number) }
            return 0
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
    var hub: HubHealthResponse.Hub?

    struct Capabilities: Decodable {
        var persistentPty: Bool?
    }
}

/// A Mac or iOS app that has connected to this hub.
struct ConnectedDevice: Decodable, Identifiable {
    var id: String
    var name: String
    var platform: String
    var appVersion: String
    /// Milliseconds since the epoch.
    var firstSeen: Double
    var lastSeen: Double
    var connected: Bool

    var lastSeenDate: Date { Date(timeIntervalSince1970: lastSeen / 1000) }

    var isThisDevice: Bool { id == DeviceIdentity.id }
}

struct DevicesResponse: Decodable {
    var data: [ConnectedDevice]
}

/// Hub behaviour the Settings tab can tune. The hub clamps values, so the
/// bounds are only used to label the controls.
struct ServerSettings: Decodable, Equatable {
    /// Coalescing window for event-stream updates; `0` forwards everything.
    var eventThrottleMs: Int
    var eventThrottleMinMs: Int?
    var eventThrottleMaxMs: Int?
}

struct ServerSettingsResponse: Decodable {
    var data: ServerSettings
}
