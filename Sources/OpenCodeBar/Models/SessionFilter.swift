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

/// Shared filtering for the recent session feeds in both apps.
enum SessionFiltering {
    static func apply(
        to sessions: [Session],
        projectID: String?,
        time: SessionTimeFilter,
        projects: [String: Project],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Session] {
        sessions.filter { session in
            if let projectID,
               !matchesProject(session, projectID: projectID, projects: projects) {
                return false
            }
            return time.contains(session.time.updatedDate, now: now, calendar: calendar)
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
