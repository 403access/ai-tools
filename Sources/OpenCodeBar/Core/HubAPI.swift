import Foundation

/// Where the hub lives and how to authenticate to it.
struct HubLocation: Equatable, Sendable {
    var url: URL
    var token: String
}

/// Errors surfaced by the hub connection. The cases mirror the old direct
/// OpenCode client so the state layer can keep its reconnect behaviour.
enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case status(Int)
    case badResponse
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid hub URL"
        case .unauthorized: return "Hub token rejected"
        case .status(let code): return "Hub returned HTTP \(code)"
        case .badResponse: return "Unexpected hub response"
        case .decoding(let detail): return "Failed to read hub response: \(detail)"
        case .transport(let detail): return detail
        }
    }

    var shouldRediscover: Bool {
        switch self {
        case .unauthorized, .badURL, .transport: return true
        default: return false
        }
    }
}

/// Go usage state as cached by the hub. `data` is the last good payload even
/// when `error` is set, which is what makes stale-but-useful limits possible.
struct HubUsageResponse: Decodable, Sendable {
    var data: GoUsage?
    var fetchedAt: Double?
    var stale: Bool?
    var error: String?
    var configured: Bool

    var fetchedDate: Date? {
        fetchedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// Health snapshot for the connection footer and settings screen.
struct HubHealthResponse: Decodable, Sendable {
    var ok: Bool?
    var version: String?
    var hub: Hub?
    var opencode: OpenCode?

    struct Hub: Decodable, Sendable {
        var version: String?
        var uptime: Int?
        var sessions: Int?
        var messages: Int?
        var projects: Int?
    }

    struct OpenCode: Decodable, Sendable {
        var connected: Bool?
        var url: String?
        var version: String?
        var lastSync: Double?
        var lastError: String?
    }
}

/// Thin async client over the OpenCodeBar hub. Endpoint shapes mirror the
/// OpenCode service so views and models work unchanged; only the transport
/// (Bearer token, cached data, hub-only endpoints) differs.
struct HubAPI: Sendable {
    let baseURL: URL
    let token: String

    init(location: HubLocation) {
        self.baseURL = location.url
        self.token = location.token
    }

    private static let decoder = JSONDecoder()

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    // MARK: - Endpoints

    func serverInfo() async throws -> ServerInfo {
        try await get("/api/info")
    }

    func health() async throws -> HubHealthResponse {
        try await get("/api/health")
    }

    func activeSessionIDs() async throws -> [String] {
        let response: ActiveSessionsResponse = try await get("/api/session/active")
        return Array(response.data.keys)
    }

    func sessions(limit: Int = 60) async throws -> [Session] {
        let response: SessionsResponse = try await get("/api/session?limit=\(limit)&order=desc")
        return response.data
    }

    func sessions(projectID: String, limit: Int = 20) async throws -> [Session] {
        let encoded = projectID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? projectID
        let response: SessionsResponse = try await get("/api/session?project=\(encoded)&limit=\(limit)&order=desc")
        return response.data
    }

    /// Direct child sessions of a parent (subagents).
    func sessions(parentID: String, limit: Int = 50) async throws -> [Session] {
        let encoded = parentID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? parentID
        let response: SessionsResponse = try await get("/api/session?parentID=\(encoded)&limit=\(limit)&order=desc")
        return response.data
    }

    func session(id: String) async throws -> Session {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: SessionEnvelope = try await get("/api/session/\(encoded)")
        return response.data
    }

    func sessionMessages(
        id: String,
        limit: Int = 100,
        cursor: String? = nil
    ) async throws -> SessionMessagesResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var path = "/api/session/\(encoded)/message?limit=\(limit)"
        if let cursor, let value = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            path += "&cursor=\(value)"
        }
        return try await get(path)
    }

    /// File patches written by a session's edit/write tool calls.
    func sessionChanges(id: String) async throws -> [FileChange] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ChangesResponse = try await get("/api/session/\(encoded)/changes")
        return response.data
    }

    /// File patches across the newest sessions in a project.
    func projectChanges(id: String, sessions: Int = 10) async throws -> [FileChange] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ChangesResponse = try await get(
            "/api/project/\(encoded)/changes?sessions=\(sessions)"
        )
        return response.data
    }

    func projects() async throws -> [Project] {
        try await get("/api/project")
    }

    func stats(project: String? = nil) async throws -> Stats {
        var path = "/api/experimental/session/stats"
        if let project {
            let encoded = project.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? project
            path += "?project=\(encoded)"
        }
        let response: StatsResponse = try await get(path)
        return response.data
    }

    func usage() async throws -> HubUsageResponse {
        try await get("/api/usage")
    }

    /// Asks the hub to pull fresh data from OpenCode. Best effort — failures are
    /// reported by the normal refresh path.
    func sync() async throws {
        _ = try await send("/api/sync", method: "POST")
    }

    // MARK: - Transport

    private func url(for path: String) throws -> URL {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        return url
    }

    private func request(_ path: String, method: String = "GET") throws -> URLRequest {
        var request = URLRequest(url: try url(for: path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
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
    func send(_ path: String, method: String = "GET") async throws -> Data {
        let request = try request(path, method: method)
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
            throw APIError.status(http.statusCode)
        }
        return data
    }

    /// Opt-in tracing, enabled with `OPENCODEBAR_DEBUG_SUBAGENTS=1`. Uses
    /// `print` rather than stderr so it compiles on iOS too.
    private static func debugLog(_ message: @autoclosure () -> String) {
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
