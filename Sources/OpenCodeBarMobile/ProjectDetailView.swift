import SwiftUI
import UIKit

struct ProjectDetailView: View {
    @EnvironmentObject var store: MobileStore
    let project: Project

    @State private var scrollToTopTrigger = 0
    @State var infoPage: ProjectInfoPage = .overview
    @State var drawerDetent: ProjectInfoDrawerDetent = .peek
    /// The drawer's live height while it is being dragged. It rests at the
    /// selected detent the rest of the time.
    @State var drawerHeight: CGFloat?
    /// The height the drawer was at when the current drag began.
    @State var dragStartHeight: CGFloat?
    /// Height available to the page, captured so toolbar actions can resize
    /// the drawer without reading a geometry proxy from the navigation bar.
    @State var drawerSpace: CGFloat = 640

    init(project: Project) {
        self.project = project
        #if DEBUG
        // Screenshot tooling:
        // SIMCTL_CHILD_OPENCODEBAR_PROJECT_DRAWER=peek|medium|expanded
        // SIMCTL_CHILD_OPENCODEBAR_PROJECT_PAGE=overview|stats|changes|files|git|sessions
        if let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_PROJECT_DRAWER"],
           let detent = ProjectInfoDrawerDetent(rawValue: requested) {
            _drawerDetent = State(initialValue: detent)
        }
        if let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_PROJECT_PAGE"],
           let page = ProjectInfoPage(rawValue: requested.capitalized) {
            _infoPage = State(initialValue: page)
        }
        #endif
    }

    var detail: MobileStore.ProjectDetail? { store.projectDetails[project.id] }
    private var running: [Session] { store.runningSessions(in: project) }

    private let topAnchor = "project-detail-top"

    /// Re-asserts the top position shortly after the push animation, so an
    /// inherited offset from the previous screen cannot leave the summary
    /// header off-screen.
    private func scrollToTop(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            proxy.scrollTo(topAnchor, anchor: .top)
        }
    }

    var body: some View {
        // Capture this before building the toolbar: SwiftUI can evaluate
        // toolbar content in a hosting context that does not inherit the
        // screen's environment objects.
        let runningCount = running.count

        return GeometryReader { geo in
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    // Lazy so a project with hundreds of running sessions only
                    // builds the rows that are on screen. The rows themselves
                    // keep live `TimelineView`s, which update in place. The
                    // rest of the project lives in the pull-up info drawer.
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            // Anchor at the top so the summary header is what a
                            // reset scrolls to, and so a push never starts below it.
                            Color.clear.frame(height: 1).id(topAnchor)

                            summary
                            runningSection

                            if running.isEmpty {
                                drawerHint
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(
                            .bottom,
                            ProjectInfoDrawerDetent.peek.height(in: geo.size.height) + 24
                        )
                    }
                    .onAppear { scrollToTop(proxy) }
                    .onChange(of: scrollToTopTrigger) { _, _ in scrollToTop(proxy) }
                    .refreshable { await refreshProject() }
                }

                drawer(available: geo.size.height)
            }
            .mobileScreenBackground()
            .onChange(of: geo.size.height, initial: true) { _, height in
                drawerSpace = height
                guard dragStartHeight == nil else { return }
                drawerHeight = drawerDetent.height(in: height)
            }
        }
        .navigationTitle(project.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    scrollToTopTrigger += 1
                    if drawerDetent != .peek {
                        setDrawer(.peek)
                    }
                } label: {
                    Text(project.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scroll to top")
                .accessibilityHint("Scrolls the project page to the top")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ProjectRunningBadge(count: runningCount)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    toggleDrawer(expand: drawerDetent == .peek)
                } label: {
                    Image(systemName: drawerDetent == .peek ? "info.circle" : "info.circle.fill")
                }
                .accessibilityLabel(
                    drawerDetent == .peek ? "Show project info" : "Hide project info"
                )
            }
        }
        .task(id: project.id) {
            store.loadProjectIcons(for: [project])
            async let detail = store.loadProject(project.id)
            async let changes = store.loadProjectChanges(project.id)
            async let files = store.loadProjectFiles(project.id)
            async let git = store.loadProjectGit(project.id)
            async let docs = store.loadProjectDocumentation(project.id)
            _ = await (detail, changes, files, git, docs)
        }
    }

    /// Reloads everything the page and its drawer can show. `refreshable`
    /// belongs to both the page scroll and the drawer's content scroll.
    func refreshProject() async {
        async let detail = store.loadProject(project.id, force: true)
        async let changes = store.loadProjectChanges(project.id, force: true)
        async let files = store.loadProjectFiles(project.id, force: true)
        async let git = store.loadProjectGit(project.id, force: true)
        async let docs = store.loadProjectDocumentation(project.id, force: true)
        _ = await (detail, changes, files, git, docs)
        await store.refreshLive()
    }

    @ViewBuilder
    var documentationSection: some View {
        let state = store.projectDocumentation[project.id]
        if let state, state.isLoading && state.documentation == nil {
            ProjectDocumentationSkeleton()
                .shimmering()
        } else if let state, let error = state.error, state.documentation == nil {
            SectionHeader("Project documentation")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let documentation = state?.documentation {
            ProjectDocumentationView(
                documentation: documentation,
                isRefreshing: state?.isLoading == true,
                onRefresh: {
                    Task { await store.loadProjectDocumentation(project.id, force: true) }
                }
            )
        }
    }

    @ViewBuilder
    var changesSection: some View {
        let state = store.projectChanges[project.id]
        if let state, state.isLoading && state.changes.isEmpty {
            SectionHeader("Changes")
            ChangesSkeleton()
                .shimmering()
        } else if let state, let error = state.error, state.changes.isEmpty {
            SectionHeader("Changes")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let changes = state?.changes, !changes.isEmpty {
            SectionHeader("Changes") {
                Text("\(Set(changes.map(\.displayPath)).count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProjectChangesView(changes: changes)
                .equatable()
        }
    }

    @ViewBuilder
    var filesSection: some View {
        let state = store.projectFiles[project.id]
        if let state, state.isLoading && state.files == nil {
            SectionHeader("Files")
            SessionListSkeleton(count: 3)
                .shimmering()
        } else if let state, let error = state.error, state.files == nil {
            SectionHeader("Files")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let files = state?.files {
            SectionHeader("Files") {
                Text("\(files.total)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            MobileProjectFilesView(files: files) {
                Task { await store.loadProjectFiles(project.id, force: true) }
            }
        }
    }

    @ViewBuilder
    var gitSection: some View {
        let state = store.projectGit[project.id]
        if let state, state.isLoading && state.repository == nil {
            SectionHeader("Git")
            LoadingState(message: "Reading repository…")
        } else if let state, let error = state.error, state.repository == nil {
            SectionHeader("Git")
            NoticeRow(
                icon: "exclamationmark.triangle.fill",
                message: error,
                tint: Theme.warn
            )
        } else if let repository = state?.repository {
            MobileGitRepositoryView(repository: repository) {
                Task { await store.loadProjectGit(project.id, force: true) }
            }
        } else if state?.isLoading == false {
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

    private var summary: some View {
        HStack(alignment: .top, spacing: 11) {
            ProjectIconTile(
                image: store.projectIcons[project.id],
                running: !running.isEmpty,
                isLoading: store.refreshingProjectIcons.contains(project.id),
                size: 42
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(project.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                CopyableRow(label: "Path", value: project.canonical)

                HStack(spacing: 5) {
                    if let vcs = project.vcs, !vcs.isEmpty {
                        Chip(text: vcs, tint: Theme.reasoning)
                    }
                    if !project.sandboxes.isEmpty {
                        Chip(
                            text: project.sandboxes.count == 1 ? "1 sandbox" : "\(project.sandboxes.count) sandboxes",
                            systemImage: "shippingbox.fill",
                            tint: .secondary
                        )
                    }
                    if let changes = store.projectChanges[project.id]?.changes, !changes.isEmpty {
                        Chip(
                            text: "\(Set(changes.map(\.displayPath)).count) files",
                            systemImage: "plus.forwardslash.minus",
                            tint: Theme.accent
                        )
                    }
                    Chip(text: "Active \(Fmt.relative(from: project.lastActiveDate))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 13)
    }

    @ViewBuilder
    private var runningSection: some View {
        let sessions = running
        if !sessions.isEmpty {
            SectionHeader("Running") {
                Text("\(sessions.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.running)
            }
            ForEach(sessions) { session in
                NavigationLink(value: session) {
                    RunningSessionRow(
                        session: session,
                        project: project.displayName,
                        activity: store.activity(for: session.id),
                        subagents: store.activeSubagentCount(for: session.id)
                    )
                }
                .buttonStyle(.plain)
                .transition(.recentInsertion)
            }
            .animateRecentInsertion(ids: sessions.map(\.id))
        }
    }

    func statsGrid(_ stats: Stats) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            StatTile(
                icon: "square.stack.3d.up.fill",
                tint: Theme.running,
                label: "Steps",
                value: Fmt.grouped(stats.steps),
                caption: "\(Fmt.grouped(stats.prompts)) prompts"
            )
            StatTile(
                icon: "dollarsign.circle.fill",
                tint: Theme.accent,
                label: "Cost",
                value: Fmt.usd(stats.cost),
                caption: "\(stats.sessions) sessions"
            )
            StatTile(
                icon: "wrench.and.screwdriver.fill",
                tint: Theme.output,
                label: "Tool calls",
                value: Fmt.grouped(stats.tools.totals?.calls ?? 0),
                caption: "\(Fmt.grouped(stats.tools.totals?.succeeded ?? 0)) succeeded"
            )
            StatTile(
                icon: "xmark.octagon.fill",
                tint: (stats.tools.totals?.failed ?? 0) > 0 ? Theme.danger : .secondary,
                label: "Failures",
                value: Fmt.grouped(stats.tools.totals?.failed ?? 0),
                caption: "\(Fmt.grouped(stats.tools.totals?.unfinished ?? 0)) unfinished"
            )
            StatTile(
                icon: "flame.fill",
                tint: Theme.warn,
                label: "Streak",
                value: "\(stats.streak)",
                caption: "\(stats.activeDays) active days"
            )
            StatTile(
                icon: "cpu",
                tint: Theme.reasoning,
                label: "Tokens",
                value: Fmt.compact(stats.tokens.generated),
                caption: "\(Fmt.compact(stats.tokens.cache.read)) cache read"
            )
        }
    }
}

/// Toolbar status with no environment dependencies, so it is safe to evaluate
/// in the navigation bar's hosting context.
private struct ProjectRunningBadge: View {
    let count: Int

    var body: some View {
        if count == 0 {
            Chip(text: "Idle")
        } else {
            HStack(spacing: 5) {
                PulsingDot(size: 6)
                Text("\(count) running")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.running)
            }
        }
    }
}

/// Compact per-model breakdown shared by the project and usage tabs.
struct ModelBreakdownCard: View, Equatable {
    let models: [Stats.ModelUsage]

    private var total: Double {
        max(models.reduce(0) { $0 + $1.cost }, 0.000_001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(models.prefix(8)) { model in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(model.model.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(Fmt.usd(model.cost))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(Theme.accent.opacity(0.65))
                                .frame(width: max(geo.size.width * CGFloat(model.cost / total), model.cost > 0 ? 3 : 0))
                        }
                    }
                    .frame(height: 4)
                    Text("\(Fmt.grouped(model.steps)) steps · \(Fmt.compact(model.tokens.generated)) tok")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }
}
