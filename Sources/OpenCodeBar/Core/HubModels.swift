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
enum PromptDelivery: String, Codable, Sendable {
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
