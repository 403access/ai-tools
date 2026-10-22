import Foundation

/// One day of usage, combining the stats API's daily steps with cost and token
/// totals derived from the session list. Used by the trend charts on the Usage
/// tab and on project detail pages.
struct DailyUsage: Identifiable, Hashable, Sendable {
    var date: Date
    var steps: Int = 0
    var cost: Double = 0
    var tokens: Double = 0

    var id: Date { date }
}

/// Window shown by the trend charts.
enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case month = "30D"
    case quarter = "90D"
    case year = "1Y"
    case all = "All"

    var id: String { rawValue }

    /// Number of days back from today, or nil for the full history.
    var days: Int? {
        switch self {
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}

/// One project's totals inside a chart window.
struct ProjectUsage: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var cost: Double
}

enum UsageSeries {
    /// Builds one point per day between the range start and today. Days without
    /// activity are kept as zeroes so gaps are visible in the chart.
    ///
    /// Day keys are formatted once for the whole window and activity entries are
    /// compared as `yyyy-MM-dd` strings, so the work scales with the number of
    /// sessions and days rather than with a formatter call per item.
    static func build(
        stats: Stats?,
        sessions: [Session],
        range: UsageRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyUsage] {
        guard stats != nil || !sessions.isEmpty else { return [] }

        let today = calendar.startOfDay(for: now)
        let start = startDate(
            stats: stats,
            sessions: sessions,
            range: range,
            today: today,
            calendar: calendar
        )
        guard start <= today else { return [] }

        let startKey = Fmt.dayString(start)
        let todayKey = Fmt.dayString(today)

        var stepsByDay: [String: Int] = [:]
        for entry in stats?.activity ?? [] {
            guard entry.date >= startKey, entry.date <= todayKey else { continue }
            stepsByDay[entry.date, default: 0] += entry.steps
        }

        struct SessionTotals {
            var cost = 0.0
            var tokens = 0.0
        }
        // One dictionary entry per day in the window; sessions then look up the
        // start-of-day date instead of formatting a new string each time.
        var dayKeys: [Date: String] = [:]
        dayKeys.reserveCapacity(366)
        var days: [Date] = []
        days.reserveCapacity(366)
        var date = start
        while date <= today {
            dayKeys[date] = Fmt.dayString(date)
            days.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        var sessionsByDay: [String: SessionTotals] = [:]
        for session in sessions {
            let day = calendar.startOfDay(for: session.time.updatedDate)
            guard let key = dayKeys[day] else { continue }
            var totals = sessionsByDay[key] ?? SessionTotals()
            totals.cost += session.cost
            totals.tokens += session.tokens.generated
            sessionsByDay[key] = totals
        }

        var points: [DailyUsage] = []
        points.reserveCapacity(days.count)
        for day in days {
            let key = dayKeys[day] ?? Fmt.dayString(day)
            let totals = sessionsByDay[key]
            points.append(
                DailyUsage(
                    date: day,
                    steps: stepsByDay[key] ?? 0,
                    cost: totals?.cost ?? 0,
                    tokens: totals?.tokens ?? 0
                )
            )
        }
        return points
    }

    /// Aggregates consecutive days so long ranges (a year, or all history) draw
    /// a readable number of bars instead of one sub-pixel mark per day.
    static func bucketed(_ points: [DailyUsage], maxPoints: Int = 120) -> [DailyUsage] {
        guard maxPoints > 1, points.count > maxPoints else { return points }
        let size = Int((Double(points.count) / Double(maxPoints)).rounded(.up))
        guard size > 1 else { return points }

        var result: [DailyUsage] = []
        result.reserveCapacity(points.count / size + 1)
        var index = 0
        while index < points.count {
            let end = min(index + size, points.count)
            var bucket = points[index]
            for point in points[(index + 1)..<end] {
                bucket.steps += point.steps
                bucket.cost += point.cost
                bucket.tokens += point.tokens
            }
            result.append(bucket)
            index = end
        }
        return result
    }

    /// Top projects by spend inside the range, for the global comparison chart.
    static func projects(
        sessions: [Session],
        projects: [String: Project],
        range: UsageRange,
        limit: Int = 5,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectUsage] {
        let today = calendar.startOfDay(for: now)
        let start = rangeStart(range: range, today: today, calendar: calendar)

        struct Totals {
            var name: String
            var cost = 0.0
        }
        var byProject: [String: Totals] = [:]
        for session in sessions {
            let date = calendar.startOfDay(for: session.time.updatedDate)
            guard date >= start, date <= today else { continue }
            let name = projects[session.projectID]?.displayName
                ?? session.directory.map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? "Unknown project"
            var totals = byProject[session.projectID] ?? Totals(name: name)
            totals.cost += session.cost
            byProject[session.projectID] = totals
        }

        return byProject
            .map { id, totals in
                ProjectUsage(id: id, name: totals.name, cost: totals.cost)
            }
            .filter { $0.cost > 0 }
            .sorted { $0.cost > $1.cost }
            .prefix(limit)
            .map { $0 }
    }

    private static func startDate(
        stats: Stats?,
        sessions: [Session],
        range: UsageRange,
        today: Date,
        calendar: Calendar
    ) -> Date {
        guard range == .all else {
            return rangeStart(range: range, today: today, calendar: calendar)
        }

        var earliest = today
        for session in sessions {
            let date = calendar.startOfDay(for: session.time.updatedDate)
            if date < earliest { earliest = date }
        }
        // Activity days are already yyyy-MM-dd strings, so take the smallest
        // lexicographically and parse only that one.
        if let earliestKey = (stats?.activity ?? []).map(\.date).min(),
           let date = Fmt.date(fromDay: earliestKey),
           date < earliest {
            earliest = date
        }
        if let from = stats?.range.fromDate, from < earliest {
            earliest = calendar.startOfDay(for: from)
        }
        return earliest
    }

    private static func rangeStart(
        range: UsageRange,
        today: Date,
        calendar: Calendar
    ) -> Date {
        guard let days = range.days else { return .distantPast }
        return calendar.date(byAdding: .day, value: -(days - 1), to: today) ?? today
    }
}

extension Stats.Range {
    var fromDate: Date { Date(timeIntervalSince1970: from / 1000) }
}
