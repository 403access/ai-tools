import Foundation

extension HubAPI {
    // MARK: - Transport

    func url(for path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        return url
    }

    func request(_ path: String, method: String = "GET") throws -> URLRequest {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (header, value) in DeviceIdentity.headers {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(path)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            DevLog.shared.record(
                "Decode failed",
                category: .api,
                level: .error,
                detail: "\(path) · \(String(describing: error))"
            )
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    func send(
        _ path: String,
        method: String = "GET",
        body: Data? = nil,
        using customSession: URLSession? = nil
    ) async throws -> Data {
        var request = try request(path, method: method)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let started = Date()
        Self.debugLog("[hub] start \(method) \(path)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (customSession ?? Self.session).data(for: request)
        } catch let error as URLError {
            Self.debugLog("[hub] url-error \(path) \(error)")
            DevLog.shared.api(
                method: method,
                path: path,
                duration: Date().timeIntervalSince(started),
                error: error.localizedDescription
            )
            throw APIError.transport(error.localizedDescription)
        } catch {
            Self.debugLog("[hub] error \(path) \(error)")
            DevLog.shared.api(
                method: method,
                path: path,
                duration: Date().timeIntervalSince(started),
                error: error.localizedDescription
            )
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            DevLog.shared.api(
                method: method,
                path: path,
                duration: Date().timeIntervalSince(started),
                error: "Not an HTTP response"
            )
            throw APIError.badResponse
        }
        let elapsed = Date().timeIntervalSince(started)
        Self.debugLog("[hub] done \(method) \(path) \(http.statusCode) \(String(format: "%.2fs", elapsed))")
        switch http.statusCode {
        case 200..<300:
            DevLog.shared.api(
                method: method,
                path: path,
                status: http.statusCode,
                duration: elapsed,
                bytes: data.count
            )
        case 401, 403:
            DevLog.shared.api(
                method: method,
                path: path,
                status: http.statusCode,
                duration: elapsed,
                error: "Unauthorized"
            )
            throw APIError.unauthorized
        default:
            let message = Self.serverMessage(from: data)
            DevLog.shared.api(
                method: method,
                path: path,
                status: http.statusCode,
                duration: elapsed,
                bytes: data.count,
                error: message
            )
            throw APIError.request(http.statusCode, message)
        }
        return data
    }

    /// Fetches best-effort image data (project icons) through the normal HTTP
    /// cache. Missing icons and transport failures both return nil so callers
    /// can fall back to a glyph without surfacing an error.
    func iconData(_ path: String) async -> Data? {
        guard var request = try? request(path) else { return nil }
        request.cachePolicy = .useProtocolCachePolicy
        do {
            let (data, response) = try await Self.iconSession.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else { return nil }
            return data
        } catch {
            return nil
        }
    }

    /// Extracts the hub's `{"error":{"message":"…"}}` payload for display.
    static func serverMessage(from data: Data) -> String {        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String,
              !message.isEmpty
        else {
            return "Hub request failed"
        }
        return message
    }

    /// Opt-in tracing, enabled with `OPENCODEBAR_DEBUG_SUBAGENTS=1`. Uses
    /// `print` rather than stderr so it compiles on iOS too.
    static func debugLog(_ message: @autoclosure () -> String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OPENCODEBAR_DEBUG_SUBAGENTS"] != nil {
            print(message())
        }
        #endif
    }

    /// Checks that a URL points at a hub, without needing the token.
    static func ping(baseURL: URL) async -> Bool {
        guard let url = URL(string: "/api/ping", relativeTo: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["hub"] as? Bool == true
        else { return false }
        return true
    }
}
