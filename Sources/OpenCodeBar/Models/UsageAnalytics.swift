import Foundation

// MARK: - Provider usage

/// One provider's slice of the selected window. Provider totals come from the
/// session list, which carries the model, cost and token counts for each
/// session; that keeps the numbers consistent with the trend and project cards
/// instead of mixing in the all-time aggregate stats payload.
struct ProviderUsage: Identifiable, Hashable, Sendable {
    /// Lowercased provider id, or `unknown` when a session has no model.
    var id: String
    var name: String
    var cost: Double = 0
    var tokens: Double = 0
    var sessions: Int = 0
    var subagents: Int = 0

    var totalSessions: Int { sessions + subagents }
}

// MARK: - Project usage

/// One project's totals inside a window, with enough detail to draw a ranked
/// comparison row rather than a single cost bar.
struct ProjectInsight: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var cost: Double = 0
    var tokens: Double = 0
    var sessions: Int = 0
    var subagents: Int = 0
    var lastUsed: Date = .distantPast

    var totalSessions: Int { sessions + subagents }
}

// MARK: - Weekdays

/// Steps, spend and session count for one day of the week. Weekdays are stored
/// Monday-first (0 = Monday) so the ranking reads like a work week regardless
/// of the user's locale.
struct WeekdayUsage: Identifiable, Hashable, Sendable {
    /// 0 = Monday … 6 = Sunday.
    var weekday: Int
    var steps: Int = 0
    var cost: Double = 0
    var tokens: Double = 0
    var sessions: Int = 0

    var id: Int { weekday }

    var name: String { UsageInsights.weekdayNames[weekday] }
    var shortName: String { UsageInsights.weekdayShortNames[weekday] }
}

// MARK: - Hours

/// Session starts in one hour of the day, local time.
struct HourUsage: Identifiable, Hashable, Sendable {
    /// 0 … 23 in the current calendar's time zone.
    var hour: Int
    var sessions: Int = 0
    var cost: Double = 0
    var tokens: Double = 0

    var id: Int { hour }

    /// "09:00" or "14:00", used by the peak callout.
    var label: String { String(format: "%02d:00", hour) }
}

/// Dense weekday × hour grid of session starts, for the punch-card heatmap.
/// Counts are stored row-major with 24 columns per day.
struct UsagePunchCard: Hashable, Sendable {
    static let hours = 24
    static let days = 7

    var counts: [Int]
    var maxCount: Int

    func count(weekday: Int, hour: Int) -> Int {
        guard (0..<Self.days).contains(weekday), (0..<Self.hours).contains(hour) else { return 0 }
        return counts[weekday * Self.hours + hour]
    }
}

// MARK: - Period totals

/// Totals for the selected window, plus the same shape for the window before
/// it so the dashboard can show period-over-period movement.
struct UsagePeriodTotals: Hashable, Sendable {
    var cost: Double = 0
    var tokens: Double = 0
    var steps: Int = 0
    /// Top-level sessions updated inside the window.
    var sessions: Int = 0
    /// Child sessions updated inside the window.
    var subagents: Int = 0
    /// Days with at least one step, used for a per-active-day average.
    var activeDays: Int = 0
}

// MARK: - Aggregation

enum UsageInsights {
    static let weekdayNames = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ]

    static let weekdayShortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    /// Display name for a provider id. OpenCode stores stable lowercase ids
    /// such as `github-copilot`; the known names keep their brand casing and
    /// anything else is title-cased from its id.
    static func providerName(_ id: String) -> String {
        switch id.lowercased() {
        case "unknown", "":
            return "Unknown"
        case "anthropic": return "Anthropic"
        case "openai": return "OpenAI"
        case "google": return "Google"
        case "opencode-go": return "OpenCode Go"
        case "opencode-zen": return "OpenCode Zen"
        case "opencode": return "OpenCode"
        case "github-copilot": return "GitHub Copilot"
        case "amazon-bedrock": return "Amazon Bedrock"
        case "azure": return "Azure"
        case "openrouter": return "OpenRouter"
        case "mistral": return "Mistral"
        case "groq": return "Groq"
        case "xai": return "xAI"
        case "deepseek": return "DeepSeek"
        case "cerebras": return "Cerebras"
        case "fireworks-ai", "fireworks": return "Fireworks AI"
        case "togetherai", "together": return "Together AI"
        case "perplexity": return "Perplexity"
        case "cohere": return "Cohere"
        default:
            return id
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map(\.capitalized)
                .joined(separator: " ")
        }
    }

    // MARK: Totals

    static func totals(
        stats: Stats?,
        sessions: [Session],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsagePeriodTotals {
        let today = calendar.startOfDay(for: now)
        return totals(
            stats: stats,
            sessions: sessions,
            from: windowStart(range: range, today: today, calendar: calendar),
            through: today,
            calendar: calendar
        )
    }

    /// The equal-length window immediately before the selected one. `nil` for
    /// the all-time range, which has no meaningful predecessor.
    static func previousTotals(
        stats: Stats?,
        sessions: [Session],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsagePeriodTotals? {
        guard let days = range.days else { return nil }
        let today = calendar.startOfDay(for: now)
        guard let currentStart = windowStart(range: range, today: today, calendar: calendar),
              let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentStart),
              let previousStart = calendar.date(
                  byAdding: .day,
                  value: -(days - 1),
                  to: previousEnd
              ) else {
            return nil
        }
        return totals(
            stats: stats,
            sessions: sessions,
            from: previousStart,
            through: previousEnd,
            calendar: calendar
        )
    }

    private static func totals(
        stats: Stats?,
        sessions: [Session],
        from start: Date?,
        through end: Date,
        calendar: Calendar
    ) -> UsagePeriodTotals {
        var totals = UsagePeriodTotals()
        let startKey = start.map(Fmt.dayString)
        let endKey = Fmt.dayString(end)

        for entry in stats?.activity ?? [] {
            guard entry.date <= endKey else { continue }
            if let startKey, entry.date < startKey { continue }
            let steps = max(entry.steps, 0)
            totals.steps += steps
            if steps > 0 { totals.activeDays += 1 }
        }

        for session in sessions where isInWindow(session.time.updatedDate, from: start, through: end, calendar: calendar) {
            totals.cost += session.cost
            totals.tokens += session.tokens.generated
            if session.isSubagent {
                totals.subagents += 1
            } else {
                totals.sessions += 1
            }
        }
        return totals
    }

    // MARK: Providers

    static func providers(
        sessions: [Session],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProviderUsage] {
        let today = calendar.startOfDay(for: now)
        let start = windowStart(range: range, today: today, calendar: calendar)
        var byProvider: [String: ProviderUsage] = [:]

        for session in sessions where isInWindow(session.time.updatedDate, from: start, through: today, calendar: calendar) {
            let rawID = session.model?.providerID ?? ""
            let id = rawID.isEmpty ? "unknown" : rawID.lowercased()
            var usage = byProvider[id] ?? ProviderUsage(id: id, name: providerName(id))
            usage.cost += session.cost
            usage.tokens += session.tokens.generated
            if session.isSubagent {
                usage.subagents += 1
            } else {
                usage.sessions += 1
            }
            byProvider[id] = usage
        }

        return byProvider.values.sorted {
            if $0.cost != $1.cost { return $0.cost > $1.cost }
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Projects

    static func projects(
        sessions: [Session],
        projects: [String: Project],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectInsight] {
        let today = calendar.startOfDay(for: now)
        let start = windowStart(range: range, today: today, calendar: calendar)
        var byProject: [String: ProjectInsight] = [:]

        for session in sessions where isInWindow(session.time.updatedDate, from: start, through: today, calendar: calendar) {
            let name = Fmt.projectName(for: session, projects: projects)
            var insight = byProject[session.projectID]
                ?? ProjectInsight(id: session.projectID, name: name)
            insight.cost += session.cost
            insight.tokens += session.tokens.generated
            if session.isSubagent {
                insight.subagents += 1
            } else {
                insight.sessions += 1
            }
            let updated = session.time.updatedDate
            if updated > insight.lastUsed { insight.lastUsed = updated }
            byProject[session.projectID] = insight
        }

        return byProject.values.sorted {
            if $0.cost != $1.cost { return $0.cost > $1.cost }
            if $0.tokens != $1.tokens { return $0.tokens > $1.tokens }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Weekdays

    /// Steps come from the stats API's daily activity; cost, tokens and session
    /// counts come from the day each session last moved, so the steps and cost
    /// toggles describe the same window.
    static func weekdays(
        stats: Stats?,
        sessions: [Session],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [WeekdayUsage] {
        let today = calendar.startOfDay(for: now)
        let start = windowStart(range: range, today: today, calendar: calendar)
        var days = (0..<UsagePunchCard.days).map { WeekdayUsage(weekday: $0) }

        let startKey = start.map(Fmt.dayString)
        let endKey = Fmt.dayString(today)
        for entry in stats?.activity ?? [] {
            guard entry.date <= endKey else { continue }
            if let startKey, entry.date < startKey { continue }
            guard let date = Fmt.date(fromDay: entry.date) else { continue }
            let index = weekdayIndex(for: date, calendar: calendar)
            days[index].steps += max(entry.steps, 0)
        }

        for session in sessions where isInWindow(session.time.updatedDate, from: start, through: today, calendar: calendar) {
            let index = weekdayIndex(for: session.time.updatedDate, calendar: calendar)
            days[index].cost += session.cost
            days[index].tokens += session.tokens.generated
            days[index].sessions += 1
        }
        return days
    }

    // MARK: Hours

    /// Sessions started in each hour. Only top-level sessions are counted so a
    /// parent and its children do not land on the same clock minute twice.
    static func hours(
        sessions: [Session],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [HourUsage] {
        let today = calendar.startOfDay(for: now)
        let start = windowStart(range: range, today: today, calendar: calendar)
        var hours = (0..<UsagePunchCard.hours).map { HourUsage(hour: $0) }

        for session in sessions where !session.isSubagent {
            let created = session.time.createdDate
            guard isInWindow(created, from: start, through: today, calendar: calendar) else { continue }
            let hour = calendar.component(.hour, from: created)
            guard hours.indices.contains(hour) else { continue }
            hours[hour].sessions += 1
            hours[hour].cost += session.cost
            hours[hour].tokens += session.tokens.generated
        }
        return hours
    }

    static func punchCard(
        sessions: [Session],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsagePunchCard {
        let today = calendar.startOfDay(for: now)
        let start = windowStart(range: range, today: today, calendar: calendar)
        var counts = Array(repeating: 0, count: UsagePunchCard.days * UsagePunchCard.hours)

        for session in sessions where !session.isSubagent {
            let created = session.time.createdDate
            guard isInWindow(created, from: start, through: today, calendar: calendar) else { continue }
            let day = weekdayIndex(for: created, calendar: calendar)
            let hour = calendar.component(.hour, from: created)
            guard (0..<UsagePunchCard.hours).contains(hour) else { continue }
            counts[day * UsagePunchCard.hours + hour] += 1
        }

        return UsagePunchCard(counts: counts, maxCount: counts.max() ?? 0)
    }

    // MARK: Helpers

    /// Start of the first day in the window, or nil for all time.
    private static func windowStart(
        range: UsageRange,
        today: Date,
        calendar: Calendar
    ) -> Date? {
        guard let days = range.days else { return nil }
        return calendar.date(byAdding: .day, value: -(days - 1), to: today)
    }

    private static func isInWindow(
        _ date: Date,
        from start: Date?,
        through end: Date,
        calendar: Calendar
    ) -> Bool {
        let day = calendar.startOfDay(for: date)
        guard day <= end else { return false }
        guard let start else { return true }
        return day >= start
    }

    /// Monday-first index (0 … 6) for a date, independent of `firstWeekday`.
    static func weekdayIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let component = calendar.component(.weekday, from: date) // 1 = Sunday
        return (component + 5) % 7
    }
}
