import Foundation

/// One decoded server-sent event. Only the fields the panel needs are kept;
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

/// Subscribes to the OpenCode server-sent event stream so the panel can update
/// the moment a session starts, stops, or produces activity.
enum EventStream {
    /// Opens a long-lived SSE connection and invokes `onEvent` for every
    /// decoded event. Reconnects with backoff until the returned task is
    /// cancelled.
    static func connect(
        location: ServiceLocation,
        onEvent: @escaping @Sendable (OpenCodeEvent) -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .background) {
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                do {
                    try await stream(location: location, onEvent: onEvent)
                    backoff = 1
                } catch {
                    // Connection dropped; fall through to the backoff delay.
                }
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
                backoff = min(backoff * 2, 20)
            }
        }
    }

    private static func stream(
        location: ServiceLocation,
        onEvent: @escaping @Sendable (OpenCodeEvent) -> Void
    ) async throws {
        let token = "opencode:\(location.password)"
        var request = URLRequest(url: location.url.appendingPathComponent("api/event"))
        request.setValue("Basic " + Data(token.utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60 * 60

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60 * 60
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, let data = payload.data(using: .utf8),
                  let event = try? JSONDecoder().decode(OpenCodeEvent.self, from: data)
            else { continue }
            onEvent(event)
        }
    }
}
