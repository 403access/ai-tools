import Foundation

/// The last known usage numbers, persisted to disk so the Usage tab can still
/// render when the OpenCode service or the console usage API is unreachable.
///
/// This is a best-effort convenience cache, not state: it lives in the user's
/// caches directory and is safe to delete at any time.
struct UsageCache: Codable {
    var stats: Stats?
    var statsFetchedAt: Date?
    var goUsage: GoUsage?
    var goUsageFetchedAt: Date?

    static let url: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("OpenCodeBar", isDirectory: true)
            .appendingPathComponent("usage.json")
    }()

    static func load() -> UsageCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(UsageCache.self, from: data)
        else { return UsageCache() }
        return cache
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: Self.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: Self.url, options: .atomic)
    }
}
