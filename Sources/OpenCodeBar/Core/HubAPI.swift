import Foundation

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

    static let decoder = JSONDecoder()

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()
}
