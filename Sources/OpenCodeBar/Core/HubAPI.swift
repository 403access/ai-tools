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

    /// Repository clones run `git clone` on the hub and can legitimately take
    /// minutes on a large project or a slow connection. The default session's
    /// 30-second resource limit would cancel them, so clones get their own.
    static let cloneSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 315
        config.timeoutIntervalForResource = 330
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    /// Project icons are immutable for long stretches and benefit from the
    /// normal HTTP cache, unlike the JSON endpoints which are always re-read.
    static let iconSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .useProtocolCachePolicy
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024
        )
        return URLSession(configuration: config)
    }()
}
