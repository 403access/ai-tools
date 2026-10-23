import Foundation

extension AppState {
    // MARK: - Subagents

    func subagentList(for parentID: String) -> SubagentList? {
        subagentLists[parentID]
    }

    func hasSubagents(_ parentID: String) -> Bool {
        !(subagentLists[parentID]?.sessions.isEmpty ?? true)
    }

    func isLoadingSubagents(_ parentID: String) -> Bool {
        subagentLists[parentID]?.isLoading == true
    }

    /// Fetches the direct child sessions of a parent. Each level is loaded when
    /// it is opened, so drilling into a child loads that child's own subagents.
    func loadSubagents(_ parentID: String, force: Bool = false) async {
        guard let api else {
            DebugLog.subagents("[subagents] no api \(parentID)")
            return
        }
        if subagentLists[parentID]?.isLoading == true { return }
        if !force, let loaded = subagentLists[parentID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&subagentLists, loadedAt: { $0.loadedAt }, pinning: parentID) }

        DebugLog.subagents("[subagents] start \(parentID)")

        var list = subagentLists[parentID] ?? SubagentList()
        list.isLoading = true
        list.error = nil
        subagentLists[parentID] = list

        do {
            let children = try await api.sessions(parentID: parentID, limit: 50)
            DebugLog.subagents("[subagents] done \(parentID) \(children.count)")
            subagentLists[parentID] = SubagentList(
                sessions: SubagentOrdering.sorted(children, activeIDs: activeIDs),
                loadedAt: Date()
            )
        } catch {
            var failed = subagentLists[parentID] ?? SubagentList()
            failed.isLoading = false
            if Task.isCancelled {
                // Navigating away cancels the view's task; do not surface that
                // as a load failure when the user comes back.
                subagentLists[parentID] = failed
                return
            }
            DebugLog.subagents("[subagents] error \(parentID) \(error)")
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            subagentLists[parentID] = failed
        }
    }

    func refreshSelectedSubagents() async {
        guard let id = selectedSession?.id, subagentLists[id] != nil else { return }
        await loadSubagents(id, force: true)
    }

    /// Folds the five-second session list into any open subagent lists so
    /// running state and cost stay current without a second fetch.
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
