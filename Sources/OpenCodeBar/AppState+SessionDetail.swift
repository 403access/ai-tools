import Foundation

extension AppState {
    // MARK: - Session detail

    /// Opens a session. Passing `from` when drilling into a subagent pushes the
    /// parent onto the back stack; opening from the task board or a project
    /// starts a fresh stack.
    func open(_ session: Session, from parent: Session? = nil) {
        if let parent, parent.id != session.id {
            if sessionStack.last?.id != parent.id {
                sessionStack.append(parent)
            }
        } else {
            sessionStack.removeAll()
        }
        selectedDevice = nil
        selectedDeploymentDevice = nil
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
        await refreshTasks(force: true)
        return session
    }

    /// Sends a prompt into an open session. Running sessions queue the message
    /// by default so it does not interrupt the current turn.
    func promptSession(
        id: String,
        text: String,
        delivery: PromptDelivery? = nil,
        startAt: Date? = nil
    ) async throws {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        try await api.promptSession(id: id, text: text, delivery: delivery, startAt: startAt)
        if startAt == nil {
            activeIDs.insert(id)
            noteTaskPrompt(id: id)
        }
        rebuildDerived()
        await refreshLive()
        await refreshTasks(force: true)
        await loadPending(id, force: true)
    }

    /// Interrupts a session and holds it until `until`. The hub continues it
    /// automatically at that time.
    func pauseSession(_ session: Session, until: Date) async throws {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        let updated = try await api.pauseSession(id: session.id, until: until)
        applyControlUpdate(updated)
        await refreshLive()
    }

    /// Interrupts a session and holds it until the user presses Continue.
    func stopSession(_ session: Session) async throws {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        let updated = try await api.stopSession(id: session.id)
        applyControlUpdate(updated)
        await refreshLive()
    }

    /// Clears a pause or stop and asks the session to continue.
    func continueSession(_ session: Session) async throws {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        let updated = try await api.continueSession(id: session.id)
        applyControlUpdate(updated, running: true)
        await refreshLive()
    }

    /// Folds a pause/stop/continue response into the lists without waiting for
    /// the next poll, so the button state changes immediately.
    private func applyControlUpdate(_ updated: Session, running: Bool = false) {
        sessions.removeAll { $0.id == updated.id }
        sessions.insert(updated, at: 0)
        sessions = SessionOrdering.mostRecentFirst(sessions)
        if running {
            activeIDs.insert(updated.id)
        } else {
            activeIDs.remove(updated.id)
            liveActivity.removeValue(forKey: updated.id)
            seedAttempts.removeValue(forKey: updated.id)
        }
        if selectedSession?.id == updated.id {
            selectedSession = updated
        }
        updateDerivedSession(updated)
        rebuildDerived()
    }

    /// Retries a failed prompt. `sameSession` resends it in the conversation so
    /// the turn can continue; `newSession` forks before the failed prompt first.
    /// The retry can optionally switch the model and agent.
    func retryTurn(
        from session: Session,
        before messageID: String?,
        prompt: String,
        model: ModelRef?,
        agent: String?,
        destination: RetryDestination
    ) async throws -> Session {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }

        var target: Session
        if destination == .newSession {
            target = try await api.forkSession(id: session.id, before: messageID)
        } else {
            target = session
        }

        if let model {
            try await api.switchModel(id: target.id, model: model)
        }
        if let agent, !agent.isEmpty {
            try await api.switchAgent(id: target.id, agent: agent)
        }
        try await api.promptSession(id: target.id, text: prompt)
        target = (try? await api.session(id: target.id)) ?? target

        sessions.removeAll { $0.id == target.id }
        sessions.insert(target, at: 0)
        sessions = SessionOrdering.mostRecentFirst(sessions)
        activeIDs.insert(target.id)
        noteTaskPrompt(id: target.id)
        if destination == .newSession, var list = forkLists[session.id] {
            list.sessions.removeAll { $0.id == target.id }
            list.sessions.insert(target, at: 0)
            forkLists[session.id] = list
        }
        rebuildDerived()
        await refreshLive()
        return target
    }

    /// Fetches the repository state around a session plus commits made while it
    /// was active. Loaded when the Git tab opens.
    func loadSessionGit(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionGit[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionGit[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&sessionGit, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionGit[sessionID] ?? SessionGitState()
        state.isLoading = true
        state.error = nil
        sessionGit[sessionID] = state

        do {
            let git = try await api.sessionGit(id: sessionID)
            sessionGit[sessionID] = SessionGitState(git: git, loadedAt: Date())
        } catch {
            var failed = sessionGit[sessionID] ?? SessionGitState()
            failed.isLoading = false
            if Task.isCancelled {
                sessionGit[sessionID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionGit[sessionID] = failed
        }
    }

    /// Models available for a session's directory.
    func modelCatalog(directory: String?) async throws -> [ModelInfo] {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        return try await api.models(directory: directory)
    }

    /// Agents available for a session's directory.
    func agentCatalog(directory: String?) async throws -> [AgentInfo] {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        return try await api.agents(directory: directory)
    }

    /// Default model OpenCode would use for a directory.
    func defaultModel(directory: String?) async throws -> ModelInfo? {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        return try await api.defaultModel(directory: directory)
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
