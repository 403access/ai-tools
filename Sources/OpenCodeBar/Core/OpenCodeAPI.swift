import Foundation

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case status(Int)
    case badResponse
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid service URL"
        case .unauthorized: return "Authentication failed"
        case .status(let code): return "Server returned HTTP \(code)"
        case .badResponse: return "Unexpected server response"
        case .decoding(let detail): return "Failed to read response: \(detail)"
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

/// Thin async client over the OpenCode HTTP API.
struct OpenCodeAPI: Sendable {
    let baseURL: URL
    let authHeader: String

    init(location: ServiceLocation) {
        self.baseURL = location.url
        let token = "opencode:\(location.password)"
        self.authHeader = "Basic " + Data(token.utf8).base64EncodedString()
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

    func activeSessionIDs() async throws -> [String] {
        let response: ActiveSessionsResponse = try await get("/api/session/active")
        return Array(response.data.keys)
    }

    func sessions(limit: Int = 60) async throws -> [Session] {
        let response: SessionsResponse = try await get("/api/session?limit=\(limit)&order=desc")
        return response.data
    }

    func sessions(projectID: String, limit: Int = 20) async throws -> [Session] {
        let response: SessionsResponse = try await get("/api/session?project=\(projectID)&limit=\(limit)&order=desc")
        return response.data
    }

    /// Direct child sessions of a parent (subagents). The parent filter is a
    /// first-class API parameter, so this does not depend on the recent list.
    func sessions(parentID: String, limit: Int = 50) async throws -> [Session] {
        let encoded = parentID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? parentID
        let response: SessionsResponse = try await get("/api/session?parentID=\(encoded)&limit=\(limit)&order=desc")
        return response.data
    }

    func session(id: String) async throws -> Session {
        let response: SessionEnvelope = try await get("/api/session/\(id)")
        return response.data
    }

    func sessionMessages(
        id: String,
        limit: Int = 100,
        cursor: String? = nil
    ) async throws -> SessionMessagesResponse {
        var path = "/api/session/\(id)/message?limit=\(limit)"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
            path += "&cursor=\(encoded)"
        }
        return try await get(path)
    }

    func projects() async throws -> [Project] {
        try await get("/api/project")
    }

    func stats(project: String? = nil) async throws -> Stats {
        var path = "/api/experimental/session/stats"
        if let project { path += "?project=\(project)" }
        let response: StatsResponse = try await get(path)
        return response.data
    }

    // MARK: - Transport

    private func request(_ path: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    func get<T: Decodable>(_ path: String) async throws -> T {
        let request = try request(path)
        let started = Date()
        DebugLog.subagents("[http] start \(path)")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch let error as URLError {
            DebugLog.subagents("[http] url-error \(path) \(error)")
            throw APIError.transport(error.localizedDescription)
        } catch {
            DebugLog.subagents("[http] error \(path) \(error)")
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        DebugLog.subagents("[http] done \(path) \(http.statusCode) \(String(format: "%.2fs", Date().timeIntervalSince(started)))")
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw APIError.unauthorized
        default:
            throw APIError.status(http.statusCode)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
