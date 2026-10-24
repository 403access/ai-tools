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
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    func send(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
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
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError {
            Self.debugLog("[hub] url-error \(path) \(error)")
            throw APIError.transport(error.localizedDescription)
        } catch {
            Self.debugLog("[hub] error \(path) \(error)")
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        Self.debugLog("[hub] done \(method) \(path) \(http.statusCode) \(String(format: "%.2fs", Date().timeIntervalSince(started)))")
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.request(http.statusCode, Self.serverMessage(from: data))
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
