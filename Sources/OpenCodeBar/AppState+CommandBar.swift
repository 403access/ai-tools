import AppKit
import Foundation

private let commandBarSessionDefaultsKey = "commandBar.agentSessionID"

@MainActor
extension AppState {
    // MARK: - Search index

    /// Everything the command bar can find, built from the state the app already
    /// keeps in memory. Projects and sessions come first so the ranking in
    /// `CommandPalette` can group them ahead of navigation and system data.
    func commandBarItems() -> [CommandItem] {
        var items: [CommandItem] = []
        items.append(contentsOf: commandBarProjectItems())
        items.append(contentsOf: commandBarSessionItems())
        items.append(contentsOf: commandBarNavigationItems())
        items.append(contentsOf: commandBarAppItems())
        items.append(contentsOf: commandBarTerminalItems())
        items.append(contentsOf: commandBarDeviceItems())
        items.append(contentsOf: commandBarActionItems())
        return items
    }

    private func commandBarProjectItems() -> [CommandItem] {
        orderedProjects.map { project in
            let running = runningByProject[project.id]?.count ?? 0
            let path = (project.canonical as NSString).abbreviatingWithTildeInPath
            let badge: String?
            let badgeTint: CommandTint

            if running > 0 {
                badge = "\(running) running"
                badgeTint = .running
            } else if let vcs = project.vcs, !vcs.isEmpty {
                badge = vcs
                badgeTint = .reasoning
            } else {
                badge = nil
                badgeTint = .secondary
            }

            return CommandItem(
                id: "project:\(project.id)",
                kind: .project,
                title: project.displayName,
                subtitle: path,
                icon: .project(project.id),
                tint: running > 0 ? .running : .accent,
                badge: badge,
                badgeTint: badgeTint,
                isRunning: running > 0,
                recency: project.lastActiveDate,
                keywords: [
                    project.id,
                    project.canonical,
                    project.name ?? "",
                    project.vcs ?? "",
                    "project",
                ] + project.sandboxes,
                action: .openProject(project.id)
            )
        }
    }

    private func commandBarSessionItems() -> [CommandItem] {
        // The live list, the full history, and the task board overlap. Keep the
        // newest representation of each session and search it once.
        var byID: [String: Session] = [:]
        byID.reserveCapacity(history.count + tasks.count + sessions.count)
        for session in history { byID[session.id] = session }
        for session in tasks { byID[session.id] = session }
        for session in sessions { byID[session.id] = session }

        return byID.values.map { session in
            let running = activeIDs.contains(session.id)
            let project = projectName(for: session)
            let updated = session.time.updatedDate

            var keywords = [
                session.id,
                project,
                session.directory ?? "",
                session.agent ?? "",
                session.model?.label ?? "",
                "session",
            ]
            if session.isSubagent { keywords.append("subagent") }
            if session.isFork { keywords.append("fork") }

            let badge = commandBarBadge(for: session, running: running)
            if let task = session.task {
                keywords.append(task.status.title)
                keywords.append(contentsOf: task.labels.map(\.title))
                if let prompt = task.queuedPrompt { keywords.append(prompt) }
            }

            return CommandItem(
                id: "session:\(session.id)",
                kind: .session,
                title: session.displayTitle,
                subtitle: "\(session.isSubagent ? "Subagent · \(project)" : project) · \(Fmt.relative(from: updated))",
                icon: .project(session.projectID),
                tint: running ? .running : .accent,
                badge: badge?.text,
                badgeTint: badge?.tint ?? .secondary,
                isRunning: running,
                recency: updated,
                keywords: keywords,
                action: .openSession(session.id)
            )
        }
    }

    private func commandBarNavigationItems() -> [CommandItem] {
        Tab.allCases.map { tab in
            CommandItem(
                id: "tab:\(tab.rawValue)",
                kind: .navigation,
                title: tab.rawValue,
                subtitle: commandBarSubtitle(for: tab),
                icon: .symbol(tab.icon),
                tint: .accent,
                badge: tab == .tasks && reviewTaskCount > 0 ? "\(reviewTaskCount) to review" : nil,
                badgeTint: .warning,
                isRunning: false,
                recency: nil,
                keywords: [tab.rawValue, "tab", "go to", commandBarSubtitle(for: tab)],
                action: .selectTab(tab.rawValue)
            )
        }
    }

    private func commandBarAppItems() -> [CommandItem] {
        guard let apps = systemInfo?.apps else { return [] }
        return apps.map { app in
            let path = (app.path as NSString).abbreviatingWithTildeInPath
            let version = app.version?.isEmpty == false ? app.version : nil
            let subtitle = [version, path].compactMap { $0 }.joined(separator: " · ")

            return CommandItem(
                id: "app:\(app.path)",
                kind: .app,
                title: app.name,
                subtitle: subtitle,
                icon: .app(path: app.path, hasIcon: app.hasIcon ?? false),
                tint: .accent,
                badge: app.source?.isEmpty == false ? app.source : nil,
                badgeTint: .secondary,
                isRunning: false,
                recency: nil,
                keywords: [
                    app.name,
                    app.path,
                    app.bundleID ?? "",
                    app.version ?? "",
                    app.source ?? "",
                    app.architecture ?? "",
                    "app",
                ],
                action: .openSystemApp(app.path)
            )
        }
    }

    private func commandBarTerminalItems() -> [CommandItem] {
        var items: [CommandItem] = []

        items.append(contentsOf: terminals.map { terminal in
            CommandItem(
                id: "terminal:\(terminal.id)",
                kind: .terminal,
                title: terminal.title.isEmpty ? terminal.commandLine : terminal.title,
                subtitle: "\(terminal.commandLine) · \(terminal.cwdLabel)",
                icon: .symbol("terminal"),
                tint: terminal.isRunning ? .running : .secondary,
                badge: terminal.isRunning ? "Running" : "Exited",
                badgeTint: terminal.isRunning ? .running : .secondary,
                isRunning: terminal.isRunning,
                recency: nil,
                keywords: [
                    terminal.id,
                    terminal.title,
                    terminal.command,
                    terminal.commandLine,
                    terminal.cwd,
                    terminal.location,
                    terminal.status,
                    "terminal",
                ],
                action: .openTerminal(terminal.id)
            )
        })

        items.append(contentsOf: hostTerminals.map { terminal in
            CommandItem(
                id: "host-terminal:\(terminal.id)",
                kind: .terminal,
                title: terminal.displayTitle,
                subtitle: "\(terminal.app) · \(terminal.shortTTY) · \(terminal.locationLabel)",
                icon: .symbol("macwindow"),
                tint: terminal.busy ? .warning : .accent,
                badge: terminal.busy ? "Busy" : "Idle",
                badgeTint: terminal.busy ? .warning : .secondary,
                isRunning: false,
                recency: nil,
                keywords: [
                    terminal.id,
                    terminal.tty,
                    terminal.title,
                    terminal.app,
                    terminal.tty,
                    terminal.processLabel,
                    "terminal",
                    "terminal.app",
                ],
                action: .openHostTerminal(terminal.id)
            )
        })

        return items
    }

    private func commandBarDeviceItems() -> [CommandItem] {
        var items: [CommandItem] = []

        items.append(contentsOf: devices.map { device in
            CommandItem(
                id: "device:\(device.id)",
                kind: .device,
                title: device.name,
                subtitle: "\(device.platform) · v\(device.appVersion) · \(device.connected ? "live" : Fmt.relative(from: device.lastSeenDate))",
                icon: .symbol(device.platformIconName),
                tint: device.connected ? .accent : .secondary,
                badge: device.connected ? "Live" : nil,
                badgeTint: .accent,
                isRunning: device.connected,
                recency: device.lastSeenDate,
                keywords: [
                    device.id,
                    device.name,
                    device.platform,
                    device.appVersion,
                    "device",
                    "app",
                ],
                action: .openDevice(device.id)
            )
        })

        items.append(contentsOf: deploymentDevices.map { device in
            CommandItem(
                id: "deployment:\(device.key)",
                kind: .device,
                title: device.name,
                subtitle: "\(device.model) · \(device.stateLabel)",
                icon: .symbol(device.icon),
                tint: device.connected ? .accent : .secondary,
                badge: device.current.isEmpty ? nil : "\(device.current.count) installed",
                badgeTint: .reasoning,
                isRunning: false,
                recency: device.lastSyncedDate,
                keywords: [
                    device.key,
                    device.name,
                    device.model,
                    device.platform,
                    device.stateLabel,
                    "device",
                    "deployment",
                ],
                action: .openDeploymentDevice(device.key)
            )
        })

        return items
    }

    private func commandBarActionItems() -> [CommandItem] {
        [
            CommandItem(
                id: "action:refresh",
                kind: .action,
                title: "Refresh now",
                subtitle: "Reload sessions, projects, usage, and system information",
                icon: .symbol("arrow.clockwise"),
                tint: .accent,
                badge: nil,
                badgeTint: .secondary,
                isRunning: false,
                recency: nil,
                keywords: ["refresh", "reload", "update", "sync"],
                action: .refresh
            ),
            CommandItem(
                id: "action:sync",
                kind: .action,
                title: "Sync hub history",
                subtitle: "Ask the hub to pull the latest OpenCode history",
                icon: .symbol("arrow.triangle.2.circlepath"),
                tint: .running,
                badge: nil,
                badgeTint: .secondary,
                isRunning: false,
                recency: nil,
                keywords: ["sync", "history", "hub", "refresh"],
                action: .sync
            ),
            CommandItem(
                id: "action:desktop-window",
                kind: .action,
                title: usesDesktopWindow ? "Close desktop window" : "Open desktop window",
                subtitle: "Switch between the full window and the menu bar panel",
                icon: .symbol(usesDesktopWindow ? "macwindow.badge.minus" : "macwindow"),
                tint: .reasoning,
                badge: nil,
                badgeTint: .secondary,
                isRunning: false,
                recency: nil,
                keywords: ["desktop", "window", "menu bar", "panel", "toggle"],
                action: .toggleDesktopWindow
            ),
        ]
    }

    private func commandBarSubtitle(for tab: Tab) -> String {
        switch tab {
        case .tasks: return "Task board and recent sessions"
        case .usage: return "Cost, tokens, tools, and streaks"
        case .projects: return "Every folder OpenCode has run in"
        case .system: return "Host inventory, apps, terminals, and files"
        case .vms: return "NixOS guests on the hub host"
        case .settings: return "Devices, server, deployments, and preferences"
        }
    }

    private func commandBarBadge(
        for session: Session,
        running: Bool
    ) -> (text: String, tint: CommandTint)? {
        if session.isPaused { return ("Paused", .warning) }
        if session.isStopped { return ("Stopped", .danger) }
        if running { return ("Running", .running) }

        if let status = session.task?.status {
            switch status {
            case .queued: return ("Queued", .warning)
            case .working: return ("In progress", .running)
            case .review: return ("Needs review", .warning)
            case .done: return ("Done", .accent)
            case .dismissed: return ("Dismissed", .secondary)
            }
        }

        if session.hasFailureOutcome { return (session.outcomeLabel, .danger) }
        return nil
    }

    // MARK: - Hydration

    /// Makes the palette useful even when the user has never opened Usage,
    /// System, or Settings: the existing fetches keep their own short caches, so
    /// opening the command bar several times does not repeat the work.
    func prepareCommandBarSearch() async {
        async let history: Void = refreshHistory()
        async let system: Void = refreshSystemInfo()
        async let terminals: Void = refreshTerminals()
        async let hostTerminals: Void = refreshHostTerminals()
        async let settings: Void = refreshSettings()
        _ = await (history, system, terminals, hostTerminals, settings)
    }

    // MARK: - Actions

    func performCommand(_ action: CommandAction) {
        switch action {
        case .openProject(let id):
            guard let project = projects[id] else { return }
            resetCommandBarNavigation()
            tab = .projects
            open(project)

        case .openSession(let id):
            guard let session = commandBarSession(id: id) else { return }
            resetCommandBarNavigation()
            tab = .tasks
            open(session)

        case .selectTab(let rawValue):
            guard let requested = Tab(rawValue: rawValue) else { return }
            resetCommandBarNavigation()
            tab = requested

        case .openSystemApp(let path):
            guard let app = systemInfo?.apps.first(where: { $0.path == path }) else { return }
            resetCommandBarNavigation()
            tab = .system
            selectedSystemApp = app

        case .openTerminal(let id):
            guard let terminal = terminals.first(where: { $0.id == id }) else { return }
            resetCommandBarNavigation()
            tab = .system
            selectedTerminal = terminal

        case .openHostTerminal(let id):
            guard let terminal = hostTerminals.first(where: { $0.id == id }) else { return }
            resetCommandBarNavigation()
            tab = .system
            selectedHostTerminal = terminal

        case .openDevice(let id):
            guard let device = devices.first(where: { $0.id == id }) else { return }
            resetCommandBarNavigation()
            tab = .settings
            open(device)

        case .openDeploymentDevice(let key):
            guard let device = deploymentDevices.first(where: { $0.key == key }) else { return }
            resetCommandBarNavigation()
            tab = .settings
            open(device)

        case .refresh:
            Task { await refreshAll() }

        case .sync:
            Task { await syncNow() }

        case .toggleDesktopWindow:
            usesDesktopWindow.toggle()
        }
    }

    // MARK: - Agent

    /// Sends free-form command-bar text to the persistent OpenCode command bar
    /// session. The agent resolves any `@` references with the opencodebar MCP
    /// tools, so requests such as "create a session in project X" act on the
    /// real projects and sessions rather than opening a search result.
    func runCommandBarPrompt(_ prompt: String) async throws -> Session {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.transport("The command is empty.")
        }
        var session = try await ensureCommandBarSession()
        do {
            try await promptSession(id: session.id, text: trimmed)
        } catch {
            // The stored session may have been deleted outside the app. Drop
            // the stale id and retry once against a fresh conversation.
            guard isMissingSession(error) else { throw error }
            UserDefaults.standard.removeObject(forKey: commandBarSessionDefaultsKey)
            session = try await ensureCommandBarSession()
            try await promptSession(id: session.id, text: trimmed)
        }
        return session
    }

    private func isMissingSession(_ error: Error) -> Bool {
        switch error {
        case APIError.status(404), APIError.request(404, _):
            return true
        default:
            return false
        }
    }

    /// Reuses one conversation so the command bar does not leave a new task
    /// behind for every prompt. A deleted session falls back to a new one.
    private func ensureCommandBarSession() async throws -> Session {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: commandBarSessionDefaultsKey), !id.isEmpty,
           let existing = await fetchSession(id: id) {
            return existing
        }

        let session = try await createSession(
            title: "Command bar",
            directory: commandBarDirectory
        )
        defaults.set(session.id, forKey: commandBarSessionDefaultsKey)
        return session
    }

    private var commandBarDirectory: String {
        if let directory = selectedSession?.directory, !directory.isEmpty {
            return directory
        }
        if let directory = selectedProject?.canonical, !directory.isEmpty {
            return directory
        }
        if let directory = orderedProjects.first?.canonical, !directory.isEmpty {
            return directory
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    // MARK: - Helpers

    private func commandBarSession(id: String) -> Session? {
        sessions.first { $0.id == id }
            ?? tasks.first { $0.id == id }
            ?? history.first { $0.id == id }
    }

    /// Leaves every detail page before a command switches context, mirroring
    /// the Back button and the sidebar's tab selection.
    private func resetCommandBarNavigation() {
        sessionStack.removeAll()
        selectedSession = nil
        selectedProject = nil
        selectedDevice = nil
        selectedDeploymentDevice = nil
        fileBrowserPath = nil
        selectedSystemApp = nil
        selectedTerminal = nil
        selectedHostTerminal = nil
    }
}
