import Combine
import Foundation

extension MobileStore {
    func loadProject(_ id: String, force: Bool = false) async {
        guard let api else { return }
        if !force, projectDetails[id]?.isLoading == true { return }
        if !force, let detail = projectDetails[id], let loaded = detail.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectDetails, loadedAt: { $0.loadedAt }, pinning: id) }

        projectDetails[id, default: ProjectDetail()].isLoading = true
        do {
            async let stats = api.stats(project: id)
            async let sessions = api.sessions(projectID: id, limit: 1_000)
            let (scopedStats, recent) = try await (stats, sessions)
            projectDetails[id] = ProjectDetail(
                stats: scopedStats,
                sessions: SessionOrdering.mostRecentFirst(recent),
                loadedAt: Date()
            )
        } catch {
            var detail = projectDetails[id] ?? ProjectDetail()
            detail.isLoading = false
            detail.error = message(for: error)
            projectDetails[id] = detail
        }
    }

    /// Loads the file patches written by one session. The hub hydrates message
    /// history on demand, so the first request can page through a long session.
    func loadChanges(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionChanges[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionChanges[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&sessionChanges, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionChanges[sessionID] ?? ChangesState()
        state.isLoading = true
        state.error = nil
        sessionChanges[sessionID] = state

        do {
            let changes = try await api.sessionChanges(id: sessionID)
            sessionChanges[sessionID] = ChangesState(
                changes: changes,
                loadedAt: Date()
            )
        } catch {
            var failed = sessionChanges[sessionID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                sessionChanges[sessionID] = failed
                return
            }
            failed.error = message(for: error)
            sessionChanges[sessionID] = failed
        }
    }

    /// Loads a session's prompts, tool reliability, failures and file totals.
    func loadSessionStats(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionStats[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionStats[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&sessionStats, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionStats[sessionID] ?? SessionStatsState()
        state.isLoading = true
        state.error = nil
        sessionStats[sessionID] = state

        do {
            let stats = try await api.sessionStats(id: sessionID)
            sessionStats[sessionID] = SessionStatsState(stats: stats, loadedAt: Date())
        } catch {
            var failed = sessionStats[sessionID] ?? SessionStatsState()
            failed.isLoading = false
            if Task.isCancelled {
                sessionStats[sessionID] = failed
                return
            }
            failed.error = message(for: error)
            sessionStats[sessionID] = failed
        }
    }

    /// Loads changes across a project's newest sessions.
    func loadProjectChanges(_ projectID: String, force: Bool = false) async {
        guard let api else { return }
        if projectChanges[projectID]?.isLoading == true { return }
        if !force, let loaded = projectChanges[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectChanges, loadedAt: { $0.loadedAt }, pinning: projectID) }

        var state = projectChanges[projectID] ?? ChangesState()
        state.isLoading = true
        state.error = nil
        projectChanges[projectID] = state

        do {
            let changes = try await api.projectChanges(id: projectID)
            projectChanges[projectID] = ChangesState(
                changes: changes,
                loadedAt: Date()
            )
        } catch {
            var failed = projectChanges[projectID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                projectChanges[projectID] = failed
                return
            }
            failed.error = message(for: error)
            projectChanges[projectID] = failed
        }
    }

    /// Loads every file in a project folder, with git working-tree status.
    func loadProjectFiles(_ projectID: String, force: Bool = false) async {
        guard let api else { return }
        if projectFiles[projectID]?.isLoading == true { return }
        if !force, let loaded = projectFiles[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectFiles, loadedAt: { $0.loadedAt }, pinning: projectID) }

        var state = projectFiles[projectID] ?? ProjectFilesState()
        state.isLoading = true
        state.error = nil
        projectFiles[projectID] = state

        do {
            let files = try await api.projectFiles(id: projectID)
            projectFiles[projectID] = ProjectFilesState(files: files, loadedAt: Date())
        } catch {
            var failed = projectFiles[projectID] ?? ProjectFilesState()
            failed.isLoading = false
            if Task.isCancelled {
                projectFiles[projectID] = failed
                return
            }
            failed.error = message(for: error)
            projectFiles[projectID] = failed
        }
    }

    func loadSubagents(_ parentID: String, force: Bool = false) async {
        guard let api else { return }
        if subagentLists[parentID]?.isLoading == true { return }
        if !force, let loaded = subagentLists[parentID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&subagentLists, loadedAt: { $0.loadedAt }, pinning: parentID) }

        var list = subagentLists[parentID] ?? SubagentList()
        list.isLoading = true
        list.error = nil
        subagentLists[parentID] = list

        do {
            let children = try await api.sessions(parentID: parentID, limit: 50)
            subagentLists[parentID] = SubagentList(
                sessions: SubagentOrdering.sorted(children, activeIDs: activeIDs),
                loadedAt: Date()
            )
        } catch {
            var failed = subagentLists[parentID] ?? SubagentList()
            failed.isLoading = false
            if Task.isCancelled {
                subagentLists[parentID] = failed
                return
            }
            failed.error = message(for: error)
            subagentLists[parentID] = failed
        }
    }

    func subagentList(for parentID: String) -> SubagentList? {
        subagentLists[parentID]
    }

    func hasSubagents(_ parentID: String) -> Bool {
        !(subagentLists[parentID]?.sessions.isEmpty ?? true)
    }

    func isLoadingSubagents(_ parentID: String) -> Bool {
        subagentLists[parentID]?.isLoading == true
    }

    func syncSubagentLists(with sessions: [Session]) {
        for parentID in Array(subagentLists.keys) {
            guard var list = subagentLists[parentID] else { continue }
            var changed = false
            for session in sessions where session.parentID == parentID {
                if let index = list.sessions.firstIndex(where: { $0.id == session.id }) {
                    if list.sessions[index] != session {
                        list.sessions[index] = session
                        changed = true
                    }
                } else {
                    list.sessions.append(session)
                    changed = true
                }
            }
            if changed {
                list.sessions = SubagentOrdering.sorted(list.sessions, activeIDs: activeIDs)
                subagentLists[parentID] = list
            }
        }
    }
}
