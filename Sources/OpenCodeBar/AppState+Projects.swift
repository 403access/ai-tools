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
