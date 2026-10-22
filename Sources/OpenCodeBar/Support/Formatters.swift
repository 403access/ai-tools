import Foundation

enum Fmt {
    /// 1200 -> "1.2k", 3_400_000 -> "3.4M"
    static func compact(_ value: Double) -> String {
        let v = abs(value)
        let sign = value < 0 ? "-" : ""
        switch v {
        case 1_000_000_000...:
            return sign + String(format: "%.1fB", v / 1_000_000_000)
        case 1_000_000...:
            return sign + String(format: "%.1fM", v / 1_000_000)
        case 100_000...:
            return sign + String(format: "%.0fk", v / 1_000)
        case 1_000...:
            return sign + String(format: "%.1fk", v / 1_000)
        default:
            return sign + String(format: "%.0f", v)
        }
    }

    static func grouped(_ value: Int) -> String {
        groupedFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// NumberFormatter allocation is expensive and `grouped` is called for every
    /// stat tile, tool row and chart label, so keep one instance around.
    private static let groupedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func usd(_ value: Double) -> String {
        if value <= 0 { return "$0.00" }
        if value < 0.01 { return String(format: "$%.4f", value) }
        if value < 1_000 { return String(format: "$%.2f", value) }
        return "$" + compact(value)
    }

    /// Short relative time, e.g. "just now", "12m ago", "3h ago", "2d ago".
    static func relative(from date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 { return "now" }
        switch seconds {
        case ..<45: return "just now"
        case ..<90: return "1m ago"
        case ..<3_600: return "\(Int(seconds / 60))m ago"
        case ..<5_400: return "1h ago"
        case ..<86_400: return "\(Int(seconds / 3_600))h ago"
        case ..<172_800: return "yesterday"
        case ..<604_800: return "\(Int(seconds / 86_400))d ago"
        default:
            return shortDateFormatter.string(from: date)
        }
    }

    /// Elapsed duration for a running session, e.g. "1h 12m", "3m 05s".
    static func elapsed(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let h = Int(seconds) / 3_600
        let m = (Int(seconds) % 3_600) / 60
        let s = Int(seconds) % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(String(format: "%02d", s))s" }
        return "\(s)s"
    }

    /// Formats a millisecond duration from the stats API.
    static func duration(milliseconds value: Double) -> String {
        elapsed(
            since: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: max(0, value) / 1_000)
        )
    }

    /// A tool's median duration, e.g. "231ms", "1.2s", "71s".
    static func milliseconds(_ value: Double) -> String {
        if value < 1_000 { return "\(Int(value.rounded()))ms" }
        return String(format: "%.1fs", value / 1_000)
    }

    /// Time until a reset, e.g. "29d 12h", "1h 21m", "45s".
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "now" }
        let minutes = Int(seconds / 60)
        let days = minutes / 1_440
        let hours = (minutes % 1_440) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(Int(seconds))s"
    }

    /// Parses an ISO 8601 timestamp, with or without fractional seconds.
    static func date(fromISO string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        return iso8601Fractional.date(from: string) ?? iso8601.date(from: string)
    }

    private static let iso8601Fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    static func date(fromDay day: String) -> Date? { dayFormatter.date(from: day) }

    static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    static func projectName(for session: Session, projects: [String: Project]) -> String {
        if let p = projects[session.projectID] { return p.displayName }
        if let dir = session.directory { return URL(fileURLWithPath: dir).lastPathComponent }
        return "Unknown project"
    }
}
