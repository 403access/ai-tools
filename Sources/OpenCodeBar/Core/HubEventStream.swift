import Foundation

/// Subscribes to the hub's event stream. The hub forwards OpenCode events
/// verbatim and adds `hub.*` notices, so the clients fold the same payloads they
/// used when talking to OpenCode directly.
enum HubEventStream {
    /// Opens a long-lived SSE connection and invokes `onEvent` for every decoded
    /// event. Reconnects with backoff until the returned task is cancelled.
    static func connect(
        baseURL: URL,
        token: String,
        onEvent: @escaping @Sendable (OpenCodeEvent) -> Void
    ) -> Task<Void, Never> {
        Task.detached(priority: .background) {
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                do {
                    try await stream(baseURL: baseURL, token: token, onEvent: onEvent)
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
        baseURL: URL,
        token: String,
        onEvent: @escaping @Sendable (OpenCodeEvent) -> Void
    ) async throws {
        guard let url = URL(string: "/api/event", relativeTo: baseURL) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (header, value) in DeviceIdentity.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        request.timeoutInterval = 60 * 60

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60 * 60
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.status((response as? HTTPURLResponse)?.statusCode ?? -1)
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
