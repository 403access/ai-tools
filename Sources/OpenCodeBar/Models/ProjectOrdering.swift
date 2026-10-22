import Foundation

/// Ordering and de-duplication for the project list.
///
/// OpenCode can keep more than one record for the same directory (a legacy
/// record alongside the live one), so both clients merge by canonical path.
/// Running counts are computed once instead of filtering the session list for
/// every comparison, which keeps this O(projects log projects + sessions)
/// rather than O(projects × sessions log projects).
enum ProjectOrdering {
    /// Number of running sessions per project id.
    static func runningCounts(
        sessions: [Session],
        activeIDs: Set<String>
    ) -> [String: Int] {
        var counts: [String: Int] = [:]
        counts.reserveCapacity(8)
        for session in sessions where activeIDs.contains(session.id) {
            counts[session.projectID, default: 0] += 1
        }
        return counts
    }

    /// Running work first, then real VCS projects, then most recently active.
    /// Duplicate records for one canonical path keep whichever ranks best.
    static func ordered(
        projects: [String: Project],
        runningCounts: [String: Int]
    ) -> [Project] {
        func ranksBelow(_ lhs: Project, than rhs: Project) -> Bool {
            let left = runningCounts[lhs.id] ?? 0
            let right = runningCounts[rhs.id] ?? 0
            if left != right { return left < right }
            let leftVCS = lhs.vcs?.isEmpty == false
            let rightVCS = rhs.vcs?.isEmpty == false
            if leftVCS != rightVCS { return !leftVCS }
            return lhs.lastActiveDate < rhs.lastActiveDate
        }

        return Dictionary(grouping: projects.values, by: \.canonical)
            .values
            .compactMap { records in records.max(by: ranksBelow) }
            .sorted { ranksBelow($1, than: $0) }
    }

    /// Groups the currently running sessions by project, most recent first.
    static func runningByProject(
        sessions: [Session],
        activeIDs: Set<String>
    ) -> [String: [Session]] {
        var grouped: [String: [Session]] = [:]
        for session in sessions where activeIDs.contains(session.id) {
            grouped[session.projectID, default: []].append(session)
        }
        for key in grouped.keys {
            grouped[key]?.sort { $0.time.updated > $1.time.updated }
        }
        return grouped
    }
}
