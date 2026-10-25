import AppKit
import Foundation

extension AppState {
    // MARK: - Projects

    /// Opens the full detail page for a project, loading its scoped stats and
    /// recent sessions on demand.
    func open(_ project: Project) {
        sessionStack.removeAll()
        selectedSession = nil
        selectedDevice = nil
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
