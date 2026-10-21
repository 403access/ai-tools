import Foundation

/// One decoded server-sent event. Only the fields the clients need are kept;
/// tool inputs are decoded lazily into `JSONValue` so individual tools can pick
/// out a command, path or todo list.
struct OpenCodeEvent: Decodable, Sendable {
    var id: String?
    var type: String
    var created: Double?
    var data: Payload?

    var date: Date? {
        created.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var sessionID: String? {
        data?.sessionID ?? data?.request?.sessionID
    }

    /// Event types that change what the Live row shows. Everything else is
    /// only used to refresh the session list.
    var updatesActivity: Bool {
        switch type {
        case "session.step.started",
             "session.reasoning.started", "session.reasoning.delta", "session.reasoning.ended",
             "session.text.started", "session.text.delta", "session.text.ended",
             "session.tool.input.started", "session.tool.called", "session.tool.progress",
             "session.tool.success", "session.tool.failed", "session.step.failed",
             "session.compaction.started", "session.compaction.ended", "session.compaction.failed",
             "session.error",
             "session.usage.updated", "permission.asked", "permission.replied":
            return true
        default:
            return false
        }
    }

    struct Payload: Decodable, Sendable {
        var sessionID: String?
        var assistantMessageID: String?
        var id: String?
        var name: String?
        var delta: String?
        var text: String?
        var input: JSONValue?
        var metadata: JSONValue?
        var cost: Double?
        var tokens: TokenUsage?
        var finish: String?
        var error: JSONValue?
        var status: String?
        var started: Double?
        var message: String?
        var action: String?
        var resources: [String]?
        var permission: String?
        var title: String?
        var request: Request?

        struct Request: Decodable, Sendable {
            var sessionID: String?
            var message: String?
            var action: String?
            var resources: [String]?
        }

        /// Human-readable text for a pending permission request. The event
        /// payload has varied between versions, so try the likely fields.
        var permissionDescription: String? {
            if let message, !message.isEmpty { return message }
            if let title, !title.isEmpty { return title }
            if let requestMessage = request?.message, !requestMessage.isEmpty { return requestMessage }
            if let action = action ?? request?.action, !action.isEmpty {
                if let resource = (resources ?? request?.resources)?.first {
                    return "\(action) · \(resource)"
                }
                return action
            }
            return permission
        }
    }
}
