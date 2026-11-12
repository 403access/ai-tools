import AppKit
import Foundation

extension AppState {
    // MARK: - Projects

    /// Clones a repository on the hub host for the New Session sheet. The
    /// caller creates the session once the folder exists.
    func cloneRepository(
        url: String,
        parent: String,
        name: String
    ) async throws -> ClonedRepository {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        return try await api.cloneRepository(url: url, parent: parent, name: name)
    }

    /// Repositories visible to the hub's GitHub login for the New Session
    /// clone flow.
    func githubRepositories() async throws -> [GitHubRepository] {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        return try await api.githubRepositories()
    }

    /// Creates an isolated checkout on the hub host for the New Session sheet.
    /// The caller creates the session once the worktree exists.
    func createWorktree(
        projectID: String,
        branch: String? = nil,
        name: String? = nil
    ) async throws -> CreatedWorktree {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        return try await api.createWorktree(projectID: projectID, branch: branch, name: name)
    }

    /// Opens the full detail page for a project, loading its scoped stats and
    /// recent sessions on demand.
    func open(_ project: Project) {
        sessionStack.removeAll()
        selectedSession = nil
        selectedDevice = nil
        selectedDeploymentDevice = nil
        fileBrowserPath = nil
        selectedProject = project
        Task { await loadProject(project.id) }
    }

    func closeProject() {
        sessionStack.removeAll()
        selectedSession = nil
        selectedProject = nil
    }

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
            detail.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectDetails[id] = detail
        }
    }

    func refreshSelectedProject() async {
        guard let project = selectedProject else { return }
        if let updated = projects[project.id] { selectedProject = updated }
        await loadProject(project.id, force: true)
        await loadProjectChanges(project.id, force: true)
        await loadProjectFiles(project.id, force: true)
        await loadProjectGit(project.id, force: true)
        if projectFlows[project.id] != nil {
            await loadProjectFlows(project.id, force: true)
        }
        if projectScripts[project.id] != nil {
            await loadProjectScripts(project.id, force: true)
        }
        if projectDocumentation[project.id] != nil {
            await loadProjectDocumentation(project.id, force: true)
        }
    }

    /// Fetches the project repository's branches, tags, and full commit graph.
    /// Loaded when the Git tab opens, so projects that are not repositories
    /// never pay for the git commands.
    func loadProjectGit(_ projectID: String, force: Bool = false) async {
        guard let api else { return }
        if projectGit[projectID]?.isLoading == true { return }
        if !force, let loaded = projectGit[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectGit, loadedAt: { $0.loadedAt }, pinning: projectID) }

        var state = projectGit[projectID] ?? ProjectGitState()
        state.isLoading = true
        state.error = nil
        projectGit[projectID] = state

        do {
            let repository = try await api.projectGit(id: projectID)
            projectGit[projectID] = ProjectGitState(repository: repository, loadedAt: Date())
        } catch {
            var failed = projectGit[projectID] ?? ProjectGitState()
            failed.isLoading = false
            if Task.isCancelled {
                projectGit[projectID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectGit[projectID] = failed
        }
    }

    /// Fetches recent GitHub Actions runs, the selected run's jobs and
    /// stages, commit stats and checks. Loaded when the Flows tab opens.
    /// `flows` stays nil when the project is not a GitHub checkout.
    func loadProjectFlows(
        _ projectID: String,
        runID: Int? = nil,
        force: Bool = false
    ) async {
        guard let api else { return }
        if projectFlows[projectID]?.isLoading == true { return }
        if !force, runID == nil, let loaded = projectFlows[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 45 {
            return
        }
        defer { trimCache(&projectFlows, loadedAt: { $0.loadedAt }, pinning: projectID) }

        var state = projectFlows[projectID] ?? ProjectFlowsState()
        state.isLoading = true
        state.error = nil
        projectFlows[projectID] = state

        do {
            let flows = try await api.projectFlows(id: projectID, runID: runID, refresh: force)
            projectFlows[projectID] = ProjectFlowsState(flows: flows, loadedAt: Date())
        } catch {
            var failed = projectFlows[projectID] ?? ProjectFlowsState()
            failed.isLoading = false
            if Task.isCancelled {
                projectFlows[projectID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectFlows[projectID] = failed
        }
    }

    /// Fetches high-level scripts declared by the project's manifests. Loaded
    /// with the Flows tab and independent of whether the project has a GitHub
    /// remote, so non-GitHub projects still show their npm or make tasks.
    func loadProjectScripts(_ projectID: String, force: Bool = false) async {
        guard let api else { return }
        if projectScripts[projectID]?.isLoading == true { return }
        if !force, let loaded = projectScripts[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectScripts, loadedAt: { $0.loadedAt }, pinning: projectID) }

        var state = projectScripts[projectID] ?? ProjectScriptsState()
        state.isLoading = true
        state.error = nil
        projectScripts[projectID] = state

        do {
            let scripts = try await api.projectScripts(id: projectID)
            projectScripts[projectID] = ProjectScriptsState(scripts: scripts, loadedAt: Date())
        } catch {
            var failed = projectScripts[projectID] ?? ProjectScriptsState()
            failed.isLoading = false
            if Task.isCancelled {
                projectScripts[projectID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectScripts[projectID] = failed
        }
    }

    /// Fetches the project brief and prompt-derived documentation. Loaded when
    /// the Docs tab opens, and refreshed after a prompt or an edit.
    func loadProjectDocumentation(_ projectID: String, force: Bool = false) async {
        guard let api else { return }
        if projectDocumentation[projectID]?.isLoading == true { return }
        if !force, let loaded = projectDocumentation[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 15 {
            return
        }
        defer {
            trimCache(
                &projectDocumentation,
                loadedAt: { $0.loadedAt },
                pinning: projectID
            )
        }

        var state = projectDocumentation[projectID] ?? ProjectDocumentationState()
        state.isLoading = true
        state.error = nil
        projectDocumentation[projectID] = state

        do {
            let documentation = try await api.projectDocumentation(id: projectID)
            projectDocumentation[projectID] = ProjectDocumentationState(
                documentation: documentation,
                loadedAt: Date()
            )
        } catch {
            var failed = projectDocumentation[projectID] ?? ProjectDocumentationState()
            failed.isLoading = false
            if Task.isCancelled {
                projectDocumentation[projectID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            projectDocumentation[projectID] = failed
        }
    }

    /// Saves the editable brief fields and replaces the cached page.
    @discardableResult
    func saveProjectDocumentation(
        _ projectID: String,
        description: String,
        mission: String,
        vision: String
    ) async throws -> ProjectDocumentation {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        let documentation = try await api.updateProjectDocumentation(
            id: projectID,
            description: description,
            mission: mission,
            vision: vision
        )
        projectDocumentation[projectID] = ProjectDocumentationState(
            documentation: documentation,
            loadedAt: Date()
        )
        return documentation
    }

    /// Fetches icons for projects that do not have one yet. Best effort: a
    /// project without usable artwork keeps the folder glyph, and a failed
    /// attempt waits five minutes before trying again.
    func loadProjectIcons(for projectList: some Sequence<Project>) {
        guard let api else { return }
        let now = Date()

        for project in projectList where projectIcons[project.id] == nil {
            if let attempted = projectIconAttempts[project.id],
               now.timeIntervalSince(attempted) < 300 {
                continue
            }
            projectIconAttempts[project.id] = now

            Task { @MainActor [weak self] in
                guard let data = await api.projectIcon(id: project.id),
                      let image = NSImage(data: data)
                else { return }
                self?.projectIcons[project.id] = image
            }
        }
    }
}
