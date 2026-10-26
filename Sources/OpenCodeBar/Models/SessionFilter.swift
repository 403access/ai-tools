import Foundation

/// Time windows for filtering the recent session feed. Presets keep the
/// filter compact instead of asking for a custom start and end date.
enum SessionTimeFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All time"
        case .today: return "Today"
        case .week: return "Last 7 days"
        case .month: return "Last 30 days"
        }
    }

    /// Compact label for the filter chip in a section header.
    var shortTitle: String {
        switch self {
        case .all: return "All time"
        case .today: return "Today"
        case .week: return "7D"
        case .month: return "30D"
        }
    }

    /// Whether `date` falls inside the window ending at `now`.
    func contains(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .week, .month:
            let days = self == .week ? 7 : 30
            guard let start = calendar.date(
                byAdding: .day,
                value: -(days - 1),
                to: calendar.startOfDay(for: now)
            ) else { return true }
            return date >= start
        }
    }
}

/// Terminal-state filters for the recent session feed. Running sessions live in
/// their own section, so these only describe how a session ended.
enum SessionStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case finished
    case failed
    case interrupted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All statuses"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        }
    }

    /// Compact label for the filter chip in a section header.
    var shortTitle: String {
        switch self {
        case .all: return "Status"
        case .finished: return "Finished"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        }
    }

    func matches(_ session: Session) -> Bool {
        switch self {
        case .all: return true
        case .finished: return !session.hasFailureOutcome
        case .failed: return session.outcome == "failed"
        case .interrupted: return session.outcome == "interrupted"
        }
    }
}

/// Day-based buckets for grouping the recent session feed. Boundaries are
/// counted in whole calendar days so rows do not drift between groups while
/// the clock moves through the day.
enum SessionTimeGroup: String, CaseIterable, Identifiable, Sendable {
    case today
    case yesterday
    case previous7Days
    case previous30Days
    case older

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .previous7Days: return "Previous 7 days"
        case .previous30Days: return "Previous 30 days"
        case .older: return "Older"
        }
    }

    /// The first matching bucket for `date`, in display order.
    static func bucket(
        for date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> SessionTimeGroup {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday { return .today }

        guard let startOfYesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: startOfToday
        ) else { return .older }
        if date >= startOfYesterday { return .yesterday }

        guard let startOf7DaysAgo = calendar.date(
            byAdding: .day,
            value: -7,
            to: startOfToday
        ) else { return .older }
        if date >= startOf7DaysAgo { return .previous7Days }

        guard let startOf30DaysAgo = calendar.date(
            byAdding: .day,
            value: -30,
            to: startOfToday
        ) else { return .older }
        if date >= startOf30DaysAgo { return .previous30Days }

        return .older
    }
}

/// A non-empty time bucket in the grouped recent feed.
struct SessionTimeGroupSection: Identifiable {
    let group: SessionTimeGroup
    let sessions: [Session]

    var id: SessionTimeGroup { group }
}

/// Splits a recent-session feed into ordered day buckets, keeping the newest
/// session first inside each bucket and omitting empty buckets.
enum SessionGrouping {
    static func groupByTime(
        _ sessions: [Session],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [SessionTimeGroupSection] {
        let ordered = SessionOrdering.mostRecentFirst(sessions)
        return SessionTimeGroup.allCases.compactMap { group in
            let matching = ordered.filter {
                SessionTimeGroup.bucket(
                    for: $0.time.updatedDate,
                    now: now,
                    calendar: calendar
                ) == group
            }
            return matching.isEmpty
                ? nil
                : SessionTimeGroupSection(group: group, sessions: matching)
        }
    }
}

/// Shared filtering for the recent session feeds in both apps.
enum SessionFiltering {
    static func apply(
        to sessions: [Session],
        projectID: String?,
        time: SessionTimeFilter,
        status: SessionStatusFilter = .all,
        projects: [String: Project],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Session] {
        sessions.filter { session in
            if let projectID,
               !matchesProject(session, projectID: projectID, projects: projects) {
                return false
            }
            guard time.contains(session.time.updatedDate, now: now, calendar: calendar) else {
                return false
            }
            return status.matches(session)
        }
    }

    /// Matches by canonical path too, so duplicate project records for the
    /// same directory filter as one project.
    static func matchesProject(
        _ session: Session,
        projectID: String,
        projects: [String: Project]
    ) -> Bool {
        if session.projectID == projectID { return true }
        guard let canonical = projects[projectID]?.canonical else { return false }
        return projects[session.projectID]?.canonical == canonical
    }
}
