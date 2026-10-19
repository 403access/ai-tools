import Foundation

/// OpenCode Go plan usage, as reported by the console's usage endpoint.
///
/// Go allowances are tracked in three windows: a rolling 5-hour window, a
/// weekly window, and the monthly allowance. Each is expressed as a percentage
/// of the model budget that has been consumed, plus the time it resets.
struct GoUsage: Codable, Hashable, Sendable {
    var rolling: Window?
    var weekly: Window?
    var monthly: Window?

    struct Window: Codable, Hashable, Sendable {
        var status: String?
        var percent: Double?
        var resetsAt: String?

        /// Percentage used, clamped to 0...100 for display.
        var used: Double { min(max(percent ?? 0, 0), 100) }

        /// The console reports `"rate-limited"` once a window is exhausted.
        var isLimited: Bool { (status ?? "").lowercased().contains("limit") }

        var resetDate: Date? { Fmt.date(fromISO: resetsAt ?? "") }
    }

    struct Response: Decodable {
        var usage: GoUsage?
    }

    /// The windows in the order the console presents them.
    var ordered: [Entry] {
        [
            rolling.map { Entry(label: "Rolling", window: $0) },
            weekly.map { Entry(label: "Weekly", window: $0) },
            monthly.map { Entry(label: "Monthly", window: $0) },
        ].compactMap { $0 }
    }

    struct Entry: Identifiable, Hashable, Sendable {
        var label: String
        var window: Window
        var id: String { label }
    }
}

enum GoUsageError: LocalizedError {
    case expiredKey
    case status(Int)
    case decoding
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .expiredKey:
            return "Go API key expired — create a new one in Console"
        case .status(let code):
            return "Console returned HTTP \(code)"
        case .decoding:
            return "Unexpected usage response"
        case .transport(let detail):
            return detail
        }
    }
}

/// Reads Go plan usage from `https://opencode.ai/zen/go/v1/usage`.
///
/// This is the same undocumented endpoint the console and the community usage
/// plugins rely on. Only the three subscription windows are exposed here; the
/// credit balance and auto-recharge setting are console-only (see NOTES.md).
enum GoUsageClient {
    static let endpoint: URL = {
        if let override = ProcessInfo.processInfo.environment["OPENCODE_GO_USAGE_URL"],
           let url = URL(string: override) { return url }
        return URL(string: "https://opencode.ai/zen/go/v1/usage")!
    }()

    /// The Go usage key, in order of precedence: `OPENCODE_GO_USAGE_KEY`,
    /// `OPENCODE_API_KEY`, the app's own `opencodebar.json` (`goUsageKey`),
    /// then the `opencode-go` entry in `auth.json` (`opencode` is accepted as
    /// a fallback for setups that store the key under the generic provider).
    static func apiKey() -> String? {
        for name in ["OPENCODE_GO_USAGE_KEY", "OPENCODE_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[name], !value.isEmpty {
                return value
            }
        }
        if let key = appConfigKey() { return key }
        let auth = ServiceDiscovery.dataDir().appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: auth),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for provider in ["opencode-go", "opencode"] {
            if let entry = root[provider] as? [String: Any],
               let key = entry["key"] as? String,
               !key.isEmpty {
                return key
            }
        }
        return nil
    }

    /// `<config>/opencode/opencodebar.json`, e.g. `{ "goUsageKey": "oc_sk_…" }`.
    ///
    /// Kept separate from `auth.json` so a read-only or service-account key can
    /// be used for usage without replacing the credential OpenCode uses for
    /// inference.
    private static func appConfigKey() -> String? {
        let url = ServiceDiscovery.configDir().appendingPathComponent("opencodebar.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = root["goUsageKey"] as? String,
              !key.isEmpty
        else { return nil }
        return key
    }

    static func fetch(key: String) async throws -> GoUsage {
        var request = URLRequest(url: endpoint)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw GoUsageError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw GoUsageError.decoding }
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw GoUsageError.expiredKey
        default:
            throw GoUsageError.status(http.statusCode)
        }
        guard let decoded = try? JSONDecoder().decode(GoUsage.Response.self, from: data),
              let usage = decoded.usage
        else { throw GoUsageError.decoding }
        return usage
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // The endpoint sits behind Cloudflare, which rejects requests without
        // a conventional user agent.
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "OpenCodeBar (+https://github.com/403access/ai-tools)",
        ]
        return URLSession(configuration: config)
    }()
}
