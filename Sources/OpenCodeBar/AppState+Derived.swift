import Foundation

extension AppState {
    // MARK: - Derived data

    var activeCount: Int { activeIDs.count }

    /// True until the first poll has produced anything to show. Screens use it
    /// to render skeletons instead of an empty state that would flash away.
    var isInitialLoading: Bool {
        lastUpdated == nil && sessions.isEmpty && stats == nil
    }

    /// Keeps the on-demand caches bounded. Opening many sessions or projects in
    /// one run would otherwise keep every message, patch and file list alive
    /// for the life of the app.
    func trimCache<T>(
        _ cache: inout [String: T],
        loadedAt: (T) -> Date?,
        limit: Int = 16,
        pinning key: String? = nil
    ) {
        guard cache.count > limit else { return }
        let kept = cache
            .sorted { (loadedAt($0.value) ?? .distantPast) > (loadedAt($1.value) ?? .distantPast) }
            .prefix(limit)
        var trimmed = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        if let key, let pinned = cache[key] { trimmed[key] = pinned }
        cache = trimmed
    }

    /// Rebuilds the feeds the views read. Called after the session list,
    /// running set or project map changes, so filtering and sorting happen once
    /// per refresh instead of on every view body evaluation.
    func rebuildDerived() {
        var running: [Session] = []
        var recent: [Session] = []
        running.reserveCapacity(min(sessions.count, activeIDs.count))
        recent.reserveCapacity(sessions.count)
        for session in sessions {
            if activeIDs.contains(session.id) {
                running.append(session)
            } else {
                recent.append(session)
            }
        }
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
    /// move on an event, without rebuilding and re-sorting the whole list.
    func updateDerivedSession(_ session: Session) {
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
}
