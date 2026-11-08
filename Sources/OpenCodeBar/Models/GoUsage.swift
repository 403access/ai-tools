import Foundation

/// OpenCode Go plan usage, as reported by the console's usage endpoint.
///
/// Go allowances are tracked in three windows: a rolling 5-hour window, a
/// weekly window, and the monthly allowance. Each is expressed as a percentage
/// of the model budget that has been consumed, plus the time it resets.
///
/// The hub fetches these numbers; clients read the cached copy from
/// `/api/usage` so no device needs its own Go key.
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

extension GoUsage {
    /// Plan identity for the Usage tab. The usage endpoint only reports
    /// allowance windows, so the name and console link are fixed.
    static let planName = "OpenCode Go"
    static let manageURL = URL(string: "https://opencode.ai/console/go")!

    /// The console reports `"rate-limited"` on an exhausted window.
    var isRateLimited: Bool { ordered.contains { $0.window.isLimited } }

    /// Soonest reset across the configured windows.
    var nextReset: Date? { ordered.compactMap(\.window.resetDate).min() }

    /// Whether the subscription is currently usable. Without any reported
    /// window there is not enough information to call it either way.
    var subscriptionStatus: String {
        if ordered.isEmpty { return "Unknown" }
        return isRateLimited ? "Rate limited" : "Active"
    }
}
