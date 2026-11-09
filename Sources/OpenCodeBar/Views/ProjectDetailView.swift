import AppKit
import SwiftUI

/// Full-panel detail for one project: at-a-glance health, scoped analytics,
/// running work, changes, files, and sessions. Opened by selecting a project on
/// the Projects tab, the same way a session row opens the session detail view.
/// A session opened from here leaves the project selected, so backing out of
/// the session returns here.
///
/// The page used to stack every section into one long scroll. It now shares the
/// session detail's segmented layout: the summary and quick actions stay fixed,
/// and each tab owns one kind of content so nothing competes for the first
/// screen.
struct ProjectDetailView: View {
    @EnvironmentObject private var state: AppState
    let project: Project
    /// False when the page is shown in the middle column of a wide desktop
    /// window and the Projects list is already visible to its left.
    let showsBackButton: Bool

    typealias Mode = AppState.ProjectDetailMode

    @State private var mode: Mode
    @State private var copiedPath = false
    @State private var showingNewSession = false
    @State private var showingDocsEditor = false
    @State private var runTerminal: SystemTerminal?
    @State private var sessionLimit = Self.sessionPageSize

    private static let sessionPageSize = 50
    private static let overviewSessionCount = 6
    private let topAnchor = "project-detail-top"

    init(project: Project, initialMode: Mode = .overview, showsBackButton: Bool = true) {
        self.project = project
        self.showsBackButton = showsBackButton
        _mode = State(initialValue: initialMode)
    }

    private var detail: AppState.ProjectDetail? { state.projectDetails[project.id] }
    private var running: [Session] { state.runningSessions(in: project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            navigationBar
            summary

            SmartTabBar(
                tabs: Mode.allCases.map { mode in
                    SmartTab(
                        value: mode,
                        title: mode.rawValue,
                        icon: mode.icon,
                        help: "Show \(mode.rawValue.lowercased())"
                    )
                },
                selection: $mode,
                accessibilityLabel: "Project sections"
            )

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Color.clear.frame(height: 1).id(topAnchor)

                        switch mode {
                        case .overview: overview
                        case .docs: docsTab
                        case .stats: statsTab
                        case .changes: changesTab
                        case .files: filesTab
                        case .structure: structureTab
                        case .git: gitTab
                        case .flows: flowsTab
                        case .sessions: sessionsTab
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: mode) { _, newMode in
                    state.projectMode = newMode
                    proxy.scrollTo(topAnchor, anchor: .top)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .task(id: project.id) {
            state.loadProjectIcons(for: [project])
            async let detail: Void = state.loadProject(project.id)
            async let changes: Void = state.loadProjectChanges(project.id)
            async let files: Void = state.loadProjectFiles(project.id)
            _ = await (detail, changes, files)
        }
        .task(id: "\(project.id)-\(mode.rawValue)") {
            if mode == .docs {
                await state.loadProjectDocumentation(project.id)
            } else if mode == .git {
                await state.loadProjectGit(project.id)
            } else if mode == .flows {
                async let flows: Void = state.loadProjectFlows(project.id)
                async let scripts: Void = state.loadProjectScripts(project.id)
                _ = await (flows, scripts)
            }
        }
        .onChange(of: project.id) { _, _ in
            sessionLimit = Self.sessionPageSize
        }
        .onExitCommand {
            state.closeProject()
        }
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet(directory: project.canonical)
                .environmentObject(state)
        }
        .sheet(isPresented: $showingDocsEditor) {
            if let documentation = state.projectDocumentation[project.id]?.documentation {
                ProjectDocumentationEditor(
                    projectName: project.displayName,
                    documentation: documentation
                ) { description, mission, vision in
                    try await state.saveProjectDocumentation(
                        project.id,
                        description: description,
                        mission: mission,
                        vision: vision
                    )
                }
            }
        }
        .sheet(item: $runTerminal, onDismiss: { runTerminal = nil }) { terminal in
            if let api = state.api {
                TerminalDetailView(terminal: terminal, api: api)
            }
        }
    }

    // MARK: - Header

    private var navigationBar: some View {
        HStack(spacing: 8) {
            if showsBackButton {
                Button {
                    state.closeProject()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("Projects")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to projects")
            } else {
                Text("Project")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if running.isEmpty {
                Chip(text: "Idle")
            } else {
                HStack(spacing: 5) {
                    PulsingDot(size: 6)
                    Text("\(running.count) running")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.running)
                }
            }
        }
    }

    /// Stays visible while the tabs scroll, so the path and quick actions are
    /// always one click away. Session and step totals live in Overview instead
    /// of repeating them here.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                ProjectIconView(
                    image: state.projectIcons[project.id],
                    running: !running.isEmpty,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)

                    Text(shortPath)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 4)

                actions
            }

            HStack(spacing: 5) {
                if let vcs = project.vcs, !vcs.isEmpty {
                    Chip(text: vcs, tint: Theme.reasoning)
                }
                if !project.sandboxes.isEmpty {
                    Chip(
                        text: "\(project.sandboxes.count) sandbox",
                        systemImage: "shippingbox.fill"
                    )
                }
                if let changes = state.projectChanges[project.id]?.changes, !changes.isEmpty {
                    Button {
                        mode = .changes
                    } label: {
                        Chip(
                            text: "\(Set(changes.map(\.displayPath)).count) changed",
                            systemImage: "plus.forwardslash.minus",
                            tint: Theme.accent
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Show changes")
                }

                Chip(
                    text: "Active \(Fmt.relative(from: project.lastActiveDate))",
                    systemImage: "clock"
                )

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
        .contextMenu {
            Button("Open in Finder") { openInFinder() }
                .disabled(!directoryExists)
            Button("Open in Terminal") { openInTerminal() }
                .disabled(!directoryExists)
            Divider()
            Button("Copy Path") { copyPath() }
        }
    }

    /// Quick actions for the project directory. Kept in the summary card so
    /// they stay visible while the tabs below scroll.
    private var actions: some View {
        HStack(spacing: 2) {
            actionButton(
                "plus",
                help: directoryExists ? "New session in this project" : "Project folder not found",
                tint: Theme.accent,
                disabled: !directoryExists
            ) {
                showingNewSession = true
            }

            actionButton(
                "folder",
                help: directoryExists ? "Open in Finder" : "Project folder not found",
                disabled: !directoryExists
            ) {
                openInFinder()
            }

            actionButton(
                "terminal",
                help: directoryExists ? "Open in Terminal" : "Project folder not found",
                disabled: !directoryExists
            ) {
                openInTerminal()
            }

            actionButton(
                copiedPath ? "checkmark" : "doc.on.doc",
                help: copiedPath ? "Path copied" : "Copy path",
                tint: copiedPath ? Theme.accent : .secondary
            ) {
                copyPath()
            }
        }
    }

    private func actionButton(
        _ icon: String,
        help: String,
        tint: Color = .secondary,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .opacity(disabled ? 0.35 : 1)
        .disabled(disabled)
        .help(help)
    }

    private var directoryURL: URL {
        URL(fileURLWithPath: project.canonical, isDirectory: true)
    }

    private var directoryExists: Bool {
        !project.canonical.isEmpty && FileManager.default.fileExists(atPath: project.canonical)
    }

    private func openInFinder() {
        NSWorkspace.shared.open(directoryURL)
    }

    private func openInTerminal() {
        guard let terminal = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            [directoryURL],
            withApplicationAt: terminal,
            configuration: configuration
        )
    }

    private func copyPath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(project.canonical, forType: .string)
        copiedPath = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedPath = false
        }
    }

    private var shortPath: String {
        (project.canonical as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Overview

    @ViewBuilder
    private var overview: some View {
        if !running.isEmpty {
            runningSection
        }

        if let detail {
            if detail.isLoading && detail.stats == nil && detail.sessions.isEmpty {
                ProjectDetailSkeleton()
                    .shimmering()
            } else {
                if let error = detail.error, detail.stats == nil {
                    NoticeRow(
                        icon: "exclamationmark.triangle.fill",
                        message: error,
                        tint: Theme.warn
                    )
                } else if let stats = detail.stats {
                    SectionHeader("At a glance")
                    ProjectStats(stats: stats)
                }

                recentSessionsPreview(detail.sessions)
            }
        } else {
            ProjectDetailSkeleton()
                .shimmering()
        }
    }

    private func recentSessionsPreview(_ sessions: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Recent sessions") {
                if sessions.count > Self.overviewSessionCount {
                    Button {
                        mode = .sessions
                    } label: {
                        Text("All \(sessions.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show every session in this project")
                } else {
                    Text("\(sessions.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if sessions.isEmpty {
                EmptyState(
                    icon: "bubble.left",
                    title: "No sessions yet",
                    subtitle: "Sessions started in this folder will show up here."
                )
            } else {
                ProjectSessions(sessions: Array(sessions.prefix(Self.overviewSessionCount)))
            }
        }
    }

    // MARK: - Docs

    @ViewBuilder
    private var docsTab: some View {
        let docsState = state.projectDocumentation[project.id]

        if let docsState, docsState.isLoading && docsState.documentation == nil {
            ProjectDocumentationSkeleton()
                .shimmering()
        } else if let docsState, let error = docsState.error, docsState.documentation == nil {
            SectionHeader("Project documentation")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let documentation = docsState?.documentation {
            ProjectDocumentationView(
                documentation: documentation,
                isRefreshing: docsState?.isLoading == true,
                onRefresh: {
                    Task { await state.loadProjectDocumentation(project.id, force: true) }
                },
                onEdit: { showingDocsEditor = true },
                onOpenSession: openDocSession
            )
        } else {
            ProjectDocumentationSkeleton()
                .shimmering()
        }
    }

    /// Opens the task that produced a documentation entry. The project's own
    /// session list is the authoritative local copy; the global list is a
    /// fallback for a session that has not been loaded into the page yet.
    private func openDocSession(_ sessionID: String) {
        let candidates = state.projectDetails[project.id]?.sessions ?? state.sessions
        guard let session = candidates.first(where: { $0.id == sessionID }) else { return }
        state.open(session)
    }

    // MARK: - Stats

    @ViewBuilder
    private var statsTab: some View {
        if let stats = detail?.stats {
            SectionHeader("Trend")
            UsageTrendCard(stats: stats, sessions: detail?.sessions ?? [])

            if let totals = stats.tools.totals {
                SectionHeader("Tool calls") {
                    if let rate = totals.successRate {
                        Text("\(Int((rate * 100).rounded()))% success")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(
                                rate >= 0.98 ? Theme.accent
                                    : rate >= 0.90 ? Theme.warn : Theme.danger
                            )
                    }
                }
                ToolSummary(totals: totals)

                if let usage = stats.tools.usage, !usage.isEmpty {
                    SectionHeader("Tools") {
                        Text("\(usage.count)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ToolUsageBreakdown(usage: usage)
                }
            }

            if !stats.models.isEmpty {
                SectionHeader("Models") {
                    Text("\(stats.models.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                ModelBreakdown(models: stats.models)
            }
        } else if let error = detail?.error {
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else {
            statsSkeleton
        }
    }

    private var statsSkeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartCardSkeleton()
            ChartCardSkeleton(height: 44)
            ChartCardSkeleton(height: 60)
        }
        .shimmering()
    }

    // MARK: - Sessions

    @ViewBuilder
    private var sessionsTab: some View {
        if let detail {
            let sessions = detail.sessions

            SectionHeader("Sessions") {
                Text("\(sessions.count)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if let error = detail.error, sessions.isEmpty {
                NoticeRow(
                    icon: "exclamationmark.triangle.fill",
                    message: error,
                    tint: Theme.warn
                )
            } else if detail.isLoading && sessions.isEmpty {
                SessionListSkeleton(count: 5)
                    .shimmering()
            } else if sessions.isEmpty {
                EmptyState(
                    icon: "bubble.left",
                    title: "No sessions yet",
                    subtitle: "Sessions started in this folder will show up here."
                )
            } else {
                let visible = Array(sessions.prefix(sessionLimit))
                ProjectSessions(sessions: visible)

                if sessions.count > sessionLimit {
                    showMoreSessionsButton(remaining: sessions.count - sessionLimit)
                }
            }
        } else {
            SessionListSkeleton(count: 5)
                .shimmering()
        }
    }

    private func showMoreSessionsButton(remaining: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                sessionLimit += Self.sessionPageSize
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text("Show \(min(remaining, Self.sessionPageSize)) more")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .help("Show more sessions")
    }

    // MARK: - Changes

    @ViewBuilder
    private var changesTab: some View {
        let changesState = state.projectChanges[project.id]

        if let changesState, changesState.isLoading && changesState.changes.isEmpty {
            SectionHeader("Changes")
            ChangesSkeleton()
                .shimmering()
        } else if let changesState, let error = changesState.error, changesState.changes.isEmpty {
            SectionHeader("Changes")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let changes = changesState?.changes, !changes.isEmpty {
            SectionHeader("Changes") {
                Text("\(Set(changes.map(\.displayPath)).count)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProjectChangesView(changes: changes)
        } else if changesState == nil {
            SectionHeader("Changes")
            ChangesSkeleton()
                .shimmering()
        } else {
            SectionHeader("Changes")
            EmptyState(
                icon: "checkmark.circle",
                title: "No changes",
                subtitle: "This project's working tree is clean."
            )
        }
    }

    // MARK: - Files

    @ViewBuilder
    private var filesTab: some View {
        let filesState = state.projectFiles[project.id]

        if let filesState, filesState.isLoading && filesState.files == nil {
            SectionHeader("Files")
            LoadingState(message: "Reading project folder…")
        } else if let filesState, let error = filesState.error, filesState.files == nil {
            SectionHeader("Files")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let files = filesState?.files {
            SectionHeader("Files") {
                Text("\(files.total)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProjectFilesView(files: files) {
                Task { await state.loadProjectFiles(project.id, force: true) }
            }
        } else {
            SectionHeader("Files")
            LoadingState(message: "Reading project folder…")
        }
    }

    // MARK: - Structure

    @ViewBuilder
    private var structureTab: some View {
        let filesState = state.projectFiles[project.id]

        if let files = filesState?.files {
            ProjectStructureTab(
                projectName: project.displayName,
                projectPath: project.canonical,
                files: files,
                loadedAt: filesState?.loadedAt
            )
        } else if let filesState, filesState.isLoading {
            SectionHeader("Structure")
            LoadingState(message: "Mapping project folders…")
        } else if let filesState, let error = filesState.error {
            SectionHeader("Structure")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else {
            SectionHeader("Structure")
            LoadingState(message: "Mapping project folders…")
        }
    }

    // MARK: - Git

    @ViewBuilder
    private var gitTab: some View {
        let gitState = state.projectGit[project.id]

        if let gitState, gitState.isLoading && gitState.repository == nil {
            SectionHeader("Git")
            LoadingState(message: "Reading repository…")
        } else if let gitState, let error = gitState.error, gitState.repository == nil {
            SectionHeader("Git")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let repository = gitState?.repository {
            GitRepositoryView(repository: repository) {
                Task { await state.loadProjectGit(project.id, force: true) }
            }
        } else if gitState?.isLoading == false {
            SectionHeader("Git")
            EmptyState(
                icon: "arrow.triangle.branch",
                title: "Not a git repository",
                subtitle: "This project folder has no git history to show."
            )
        } else {
            SectionHeader("Git")
            LoadingState(message: "Reading repository…")
        }
    }

    // MARK: - Flows

    @ViewBuilder
    private var flowsTab: some View {
        let flowsState = state.projectFlows[project.id]
        let scriptsState = state.projectScripts[project.id]
        let hasScripts = scriptsState?.scripts?.scripts.isEmpty == false
        let showScripts = hasScripts
            || scriptsState?.error != nil
            || (scriptsState?.isLoading == true && scriptsState?.scripts == nil)

        VStack(alignment: .leading, spacing: 12) {
            if showScripts {
                ProjectScriptsView(
                    scripts: scriptsState?.scripts,
                    isLoading: scriptsState?.isLoading == true,
                    error: scriptsState?.error,
                    onRefresh: {
                        Task { await state.loadProjectScripts(project.id, force: true) }
                    },
                    onRun: { script in
                        let terminal = try await state.runProjectScript(
                            script,
                            projectID: project.id
                        )
                        runTerminal = terminal
                    }
                )
            }

            flowsContent(flowsState, hasScripts: hasScripts)
        }
    }

    @ViewBuilder
    private func flowsContent(
        _ flowsState: AppState.ProjectFlowsState?,
        hasScripts: Bool
    ) -> some View {
        if let flows = flowsState?.flows {
            ProjectFlowsView(
                flows: flows,
                isLoading: flowsState?.isLoading == true,
                onSelectRun: { run in
                    Task {
                        await state.loadProjectFlows(project.id, runID: run.id, force: true)
                    }
                },
                onRefresh: {
                    Task {
                        async let flows: Void = state.loadProjectFlows(project.id, force: true)
                        async let scripts: Void = state.loadProjectScripts(project.id, force: true)
                        _ = await (flows, scripts)
                    }
                }
            )
        } else if let flowsState, flowsState.isLoading {
            FlowsSkeleton()
                .shimmering()
        } else if let flowsState, let error = flowsState.error {
            SectionHeader("Flows")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if flowsState?.loadedAt != nil {
            if hasScripts {
                Text("No GitHub remote, so only local scripts are shown.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                SectionHeader("Flows")
                EmptyState(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "Not a GitHub project",
                    subtitle: "Add a GitHub remote to this checkout to see Actions runs and checks."
                )
            }
        } else {
            FlowsSkeleton()
                .shimmering()
        }
    }

    // MARK: - Running

    @ViewBuilder
    private var runningSection: some View {
        let sessions = running
        SectionHeader("Running") {
            Text("\(sessions.count)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Theme.running)
        }

        VStack(spacing: 0) {
            ForEach(sessions) { session in
                Button {
                    state.open(session)
                } label: {
                    ProjectSessionRow(session: session, running: true)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Show conversation and prompts")
                .transition(.recentInsertion)

                if session.id != sessions.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
        .card(padding: 10)
        .animateRecentInsertion(ids: sessions.map(\.id))
    }
}
