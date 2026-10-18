import Foundation

/// Subscribes to the OpenCode server-sent event stream so the panel can update
/// the moment a session starts, stops, or produces activity.
enum EventStream {
    private struct Event: Decodable {
        var type: String
    }

    /// Opens a long-lived SSE connection and invokes `onActivity` for events
    /// that are likely to change what the panel displays. Reconnects with
    /// backoff until the returned task is cancelled.
    static func connect(location: ServiceLocation, onActivity: @escaping @Sendable () -> Void) -> Task<Void, Never> {
        Task.detached(priority: .background) {
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                do {
                    try await stream(location: location, onActivity: onActivity)
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

    private static func stream(location: ServiceLocation, onActivity: @escaping @Sendable () -> Void) async throws {
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
                  let event = try? JSONDecoder().decode(Event.self, from: data)
            else { continue }
            if event.type == "server.connected"
                || event.type.hasPrefix("session.")
                || event.type.hasPrefix("message.") {
                onActivity()
            }
        }
    }
}
