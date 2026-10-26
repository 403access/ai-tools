import Foundation

// MARK: - Session messages

/// Arbitrary JSON, used for tool inputs and metadata whose shape varies by tool.
enum JSONValue: Codable, Hashable, Sendable {
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let values): try container.encode(values)
        case .object(let values): try container.encode(values)
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

/// One prompt the session has accepted but not delivered to the model yet.
/// OpenCode calls these inbox items; the apps present them as a pending queue.
struct SessionPending: Decodable, Identifiable, Equatable, Sendable {
    var id: String
    var sessionID: String
    var type: String
    var time: Time
    var delivery: PromptDelivery?
    /// User inputs carry `{text: …}`; compaction and move items carry other
    /// shapes, so keep the payload loose and read the text only when present.
    var payload: JSONValue?

    struct Time: Decodable, Equatable, Sendable {
        var created: Double

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
    }

    /// Only user prompts are shown; compaction and move items are internal.
    var isUserPrompt: Bool { type == "user" }

    var promptText: String? {
        guard case .object(let fields)? = payload,
              case .string(let text)? = fields["text"]
        else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var deliveryLabel: String {
        delivery == .steer ? "Steer" : "Queued"
    }
}

struct SessionPendingResponse: Decodable {
    var data: [SessionPending]
}

struct SessionMessage: Codable, Identifiable, Equatable {
    var id: String
    var type: String
    var time: Time
    var text: String?
    var content: [MessagePart]?
    var model: ModelRef?
    var agent: String?
    var cost: Double?
    var tokens: TokenUsage?
    var outcome: String?
    var finish: String?
    var error: SessionMessageError?
    var retry: SessionMessageRetry?

    struct Time: Codable, Equatable {
        var created: Double
        var streamed: Double?
        var completed: Double?

        var createdDate: Date { Date(timeIntervalSince1970: created / 1000) }
    }

    var isUserLike: Bool { type == "user" || type == "synthetic" }
    var isSynthetic: Bool { type == "synthetic" }
    var isIdle: Bool { type == "idle" }
    var hasError: Bool { error != nil }
    var roleLabel: String {
        switch type {
        case "user": return "You"
        case "synthetic": return "System"
        case "idle", "system": return "Status"
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

    /// Idle status rows only matter when they explain a failure; successful
    /// ones are bookkeeping and should not appear as empty assistant cards.
    var isVisibleStatus: Bool {
        !isIdle || error != nil || outcome == "failed" || outcome == "interrupted"
    }
}

/// A failure OpenCode recorded on a turn or message.
struct SessionMessageError: Codable, Equatable, Hashable, Sendable {
    var type: String?
    var message: String?
    var status: Int?
    var response: Body?
    var retryAfterMs: Int?

    struct Body: Codable, Equatable, Hashable, Sendable {
        var body: String?
    }

    /// The most useful human-readable line, preferring the structured message.
    var displayMessage: String {
        if let message, !message.isEmpty { return message }
        if let body = response?.body, !body.isEmpty {
            return body
        }
        if let type, !type.isEmpty { return type }
        return "The turn failed."
    }

    var detailLine: String? {
        var parts: [String] = []
        if let type, !type.isEmpty { parts.append(type) }
        if let status { parts.append("HTTP \(status)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// One provider retry OpenCode attempted before a turn settled.
struct SessionMessageRetry: Codable, Equatable, Hashable, Sendable {
    var attempt: Int?
    var at: Double?
    var error: SessionMessageError?

    var atDate: Date? {
        at.map { Date(timeIntervalSince1970: $0 / 1000) }
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

struct MessagePart: Codable, Equatable {
    var type: String
    var id: String?
    var text: String?
    var name: String?
    var state: ToolState?
    var time: Time?

    struct Time: Codable, Equatable {
        var created: Double?
        var ran: Double?
        var completed: Double?
    }

    struct ToolState: Codable, Equatable {
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
