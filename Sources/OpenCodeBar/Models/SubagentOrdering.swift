import Foundation

/// Running work first, then the most recently active. Used by the subagent
/// list on a session's detail page.
enum SubagentOrdering {
    static func sorted(_ sessions: [Session], activeIDs: Set<String>) -> [Session] {
        sessions.sorted { lhs, rhs in
            let leftRunning = activeIDs.contains(lhs.id)
            let rightRunning = activeIDs.contains(rhs.id)
            if leftRunning != rightRunning { return leftRunning }
            if lhs.time.updated != rhs.time.updated {
                return lhs.time.updated > rhs.time.updated
            }
            return lhs.id < rhs.id
        }
    }
}
