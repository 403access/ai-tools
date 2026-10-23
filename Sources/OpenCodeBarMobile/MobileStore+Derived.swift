import Combine
import Foundation

extension MobileStore {
    // MARK: - Derived data

    func activity(for sessionID: String) -> SessionActivity? {
        liveActivity[sessionID]
    }

    func isRunning(_ session: Session) -> Bool {
        activeIDs.contains(session.id)
    }

    func session(id: String) -> Session? {
        if let match = sessionsByID[id] { return match }
        for list in subagentLists.values {
            if let match = list.sessions.first(where: { $0.id == id }) { return match }
        }
        for detail in projectDetails.values {
            if let match = detail.sessions.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    var activeCount: Int { activeIDs.count }

    /// True until the first poll has produced anything to show.
    var isInitialLoading: Bool {
        lastUpdated == nil && sessions.isEmpty && stats == nil
    }

    /// Rebuilds the feeds the views read. Called after the session list,
    /// running set or project map changes, so filtering and sorting happen once
    /// per refresh rather than on every view body evaluation.
    func rebuildDerived() {
        var running: [Session] = []
        var recent: [Session] = []
        var byID: [String: Session] = [:]
        running.reserveCapacity(min(sessions.count, activeIDs.count))
        recent.reserveCapacity(sessions.count)
        byID.reserveCapacity(sessions.count)
        for session in sessions {
            byID[session.id] = session
            if activeIDs.contains(session.id) {
                running.append(session)
            } else {
                recent.append(session)
            }
        }
        sessionsByID = byID
        running.sort { $0.time.updated > $1.time.updated }
        recent.sort { $0.time.updated > $1.time.updated }

        if running != runningSessions { runningSessions = running }
        if recent != recentSessions { recentSessions = recent }

        runningByProject = ProjectOrdering.runningByProject(sessions: sessions, activeIDs: activeIDs)
        var counts: [String: Int] = [:]
        for session in sessions where activeIDs.contains(session.id) {
            if let parentID = session.parentID {
                counts[parentID, default: 0] += 1
            }
        }
        subagentCounts = counts

        let ordered = ProjectOrdering.ordered(
            projects: projects,
            runningCounts: runningByProject.mapValues(\.count)
        )
        if ordered != orderedProjects { orderedProjects = ordered }

        var names: [String: String] = [:]
        names.reserveCapacity(projects.count)
        for project in projects.values {
            names[project.id] = project.displayName
        }
        projectNames = names
    }

    /// Keeps the derived feeds in step when a single session's cost or tokens
    /// move on an event, without rebuilding the whole list.
    func updateDerivedSession(_ session: Session) {
        sessionsByID[session.id] = session
        if let index = runningSessions.firstIndex(where: { $0.id == session.id }) {
            runningSessions[index] = session
        }
        if let index = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[index] = session
        }
    }

    func runningSessions(in project: Project) -> [Session] {
        runningByProject[project.id] ?? []
    }

    func activeSubagentCount(for sessionID: String) -> Int {
        subagentCounts[sessionID] ?? 0
    }

    func projectName(for session: Session) -> String {
        if let name = projectNames[session.projectID] { return name }
        return Fmt.projectName(for: session, projects: projects)
    }

    var todaySteps: Int {
        stats?.steps(onDay: Fmt.dayString(Date())) ?? 0
    }

    func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
