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
    /// A hub request failed with a server-provided message.
    case request(Int, String)
    case badResponse
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid hub URL"
        case .unauthorized: return "Hub token rejected"
        case .status(let code): return "Hub returned HTTP \(code)"
        case .request(let code, let message): return "\(message) (HTTP \(code))"
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
struct HubUsageResponse: Codable, Sendable {
    var data: GoUsage?
    var fetchedAt: Double?
    var stale: Bool?
    var error: String?
    var configured: Bool

    var fetchedDate: Date? {
        fetchedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}

/// How a message should be admitted while a session is already running.
enum PromptDelivery: String, Encodable, Sendable {
    /// Wait for the current run to finish, then start a new turn.
    case queue
    /// Deliver into the current turn.
    case steer
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
        var db: String?
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

/// Incremental change feed returned by `GET /api/sync`. A `full` response
/// replaces the local copy; otherwise only the listed rows changed.
struct HubSyncResponse: Decodable, Sendable {
    var revision: Int
    var full: Bool
    var sessions: [Session]
    var deletedSessions: [String]
    var projects: [Project]
    var deletedProjects: [String]
    var active: [String]
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

    /// Mac and iOS apps known to the hub, including which ones are live now.
    func devices() async throws -> [ConnectedDevice] {
        let response: DevicesResponse = try await get("/api/devices")
        return response.data
    }

    /// Current hub behaviour, including the event update throttle.
    func settings() async throws -> ServerSettings {
        let response: ServerSettingsResponse = try await get("/api/settings")
        return response.data
    }

    /// Changes the coalescing window for updates sent to the apps. The hub
    /// applies it immediately and persists it for the next launch.
    func updateSettings(eventThrottleMs: Int) async throws -> ServerSettings {
        let body = try JSONEncoder().encode(["eventThrottleMs": eventThrottleMs])
        let data = try await send("/api/settings", method: "PATCH", body: body)
        do {
            return try Self.decoder.decode(ServerSettingsResponse.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Restarts the hub process. The connection may drop briefly while it
    /// rebinds its port.
    func restartServer() async throws {
        _ = try await send("/api/server/restart", method: "POST")
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

    /// Starts a new session in a project directory. The hub asks OpenCode to
    /// pick the default agent and model.
    func createSession(title: String?, directory: String) async throws -> Session {
        struct Location: Encodable { var directory: String }
        struct Body: Encodable {
            var title: String?
            var location: Location
        }

        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body = Body(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            location: Location(directory: directory)
        )
        let data = try await send(
            "/api/session",
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
        do {
            return try Self.decoder.decode(SessionEnvelope.self, from: data).data
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a prompt into an existing session. If the session is running,
    /// `delivery` decides whether the message waits or steers the current turn.
    func promptSession(id: String, text: String, delivery: PromptDelivery? = nil) async throws {
        struct Body: Encodable {
            var text: String
            var delivery: PromptDelivery?
        }

        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let body = Body(text: text, delivery: delivery)
        _ = try await send(
            "/api/session/\(encoded)/prompt",
            method: "POST",
            body: try JSONEncoder().encode(body)
        )
    }

    func sessionMessages(
        id: String,
        limit: Int = 100,
        cursor: String? = nil,
        since: Double? = nil
    ) async throws -> SessionMessagesResponse {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        var path = "/api/session/\(encoded)/message?limit=\(limit)"
        if let cursor, let value = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            path += "&cursor=\(value)"
        }
        if let since, since.isFinite, since > 0 {
            path += "&since=\(Int(since))"
        }
        return try await get(path)
    }

    /// File patches written by a session's edit/write tool calls.
    func sessionChanges(id: String) async throws -> [FileChange] {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ChangesResponse = try await get("/api/session/\(encoded)/changes")
        return response.data
    }

    /// Per-session prompts, steps, tool reliability, failures and file totals.
    func sessionStats(id: String) async throws -> SessionStats {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: SessionStatsResponse = try await get("/api/session/\(encoded)/stats")
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

    /// Every file in the project folder, with git working-tree status when the
    /// project is a repository.
    func projectFiles(id: String) async throws -> ProjectFiles {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let response: ProjectFilesResponse = try await get("/api/project/\(encoded)/files")
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

    /// Fetches only the sessions and projects that changed after `since`.
    /// Passing `nil` asks for a full snapshot (first launch, or after a reset).
    func sync(since: Int?) async throws -> HubSyncResponse {
        if let since {
            return try await get("/api/sync?since=\(since)")
        }
        return try await get("/api/sync")
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

    /// Extracts the hub's `{"error":{"message":"…"}}` payload for display.
    private static func serverMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
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
