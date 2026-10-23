import Foundation

extension AppState {
    // MARK: - Session detail

    /// Opens a session. Passing `from` when drilling into a subagent pushes the
    /// parent onto the back stack; opening from the Live tab or a project
    /// starts a fresh stack.
    func open(_ session: Session, from parent: Session? = nil) {
        if let parent, parent.id != session.id {
            if sessionStack.last?.id != parent.id {
                sessionStack.append(parent)
            }
        } else {
            sessionStack.removeAll()
        }
        selectedSession = session
        Task { await loadSubagents(session.id) }
    }

    func closeDetail() {
        if let previous = sessionStack.popLast() {
            selectedSession = sessions.first(where: { $0.id == previous.id }) ?? previous
        } else {
            selectedSession = nil
        }
    }

    /// Title of the session detail view's back button. A drilled-in session
    /// returns to its parent; everything else returns to the project or Live.
    var sessionBackTitle: String {
        if let previous = sessionStack.last {
            let latest = sessions.first(where: { $0.id == previous.id }) ?? previous
            return latest.displayTitle
        }
        return selectedProject?.displayName ?? "Live"
    }

    func isRunning(_ session: Session) -> Bool {
        activeIDs.contains(session.id)
    }

    /// Fetches conversation messages, newest first. Pass a cursor from a
    /// previous response to page further back in the session.
    func messages(
        for sessionID: String,
        limit: Int = 100,
        cursor: String? = nil
    ) async throws -> SessionMessagesResponse {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        return try await api.sessionMessages(id: sessionID, limit: limit, cursor: cursor)
    }

    /// Creates a session in `directory` and opens it. Used by the New Session
    /// sheet on the Live and Project detail views.
    func createSession(title: String?, directory: String) async throws -> Session {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        let session = try await api.createSession(title: title, directory: directory)
        sessions.insert(session, at: 0)
        rebuildDerived()
        sessionStack.removeAll()
        selectedSession = session
        await refreshLive()
        return session
    }

    /// Sends a prompt into an open session. Running sessions queue the message
    /// by default so it does not interrupt the current turn.
    func promptSession(
        id: String,
        text: String,
        delivery: PromptDelivery? = nil
    ) async throws {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        try await api.promptSession(id: id, text: text, delivery: delivery)
        activeIDs.insert(id)
        rebuildDerived()
        await refreshLive()
        await loadPending(id, force: true)
    }

    /// Fetches the prompts a session has accepted but not delivered yet.
    func loadPending(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionPending[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionPending[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 5 {
            return
        }
        defer { trimCache(&sessionPending, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionPending[sessionID] ?? PendingState()
        state.isLoading = true
        state.error = nil
        sessionPending[sessionID] = state

        do {
            let items = try await api.sessionPending(id: sessionID)
            sessionPending[sessionID] = PendingState(items: items, loadedAt: Date())
        } catch {
            var failed = sessionPending[sessionID] ?? PendingState()
            failed.isLoading = false
            failed.loadedAt = Date()
            if Task.isCancelled {
                sessionPending[sessionID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionPending[sessionID] = failed
        }
    }

    /// Withdraws one queued prompt before the running turn consumes it.
    func cancelPending(_ sessionID: String, itemID: String) async throws {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        try await api.cancelPending(id: sessionID, pendingID: itemID)
        if var state = sessionPending[sessionID] {
            state.items.removeAll { $0.id == itemID }
            sessionPending[sessionID] = state
        }
    }

    /// Fetches the file patches written by a session. The hub hydrates message
    /// history on demand, so the first call may page through a long session.
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
            sessionChanges[sessionID] = ChangesState(changes: changes, loadedAt: Date())
        } catch {
            var failed = sessionChanges[sessionID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                sessionChanges[sessionID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionChanges[sessionID] = failed
        }
    }

    /// Fetches a session's tool-use and failure summary. The hub hydrates the
    /// message history on the first request, so this can take a moment.
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
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionStats[sessionID] = failed
        }
    }

    /// Refreshes the open session's stats on the slow cycle.
    func refreshSelectedSessionStats() async {
        guard let id = selectedSession?.id, sessionStats[id]?.stats != nil else { return }
        await loadSessionStats(id, force: true)
    }

    /// Fetches changes across a project's newest sessions.
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
            projectChanges[projectID] = ChangesState(changes: changes, loadedAt: Date())
        } catch {
            var failed = projectChanges[projectID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                projectChanges[projectID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectChanges[projectID] = failed
        }
    }

    /// Fetches the files in a project folder. The hub reads the directory and
    /// reports git working-tree status, so this is refreshed when the page
    /// reopens or the user asks for a refresh.
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
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectFiles[projectID] = failed
        }
    }
}
