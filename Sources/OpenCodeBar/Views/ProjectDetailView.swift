import AppKit
import SwiftUI

/// Full-panel detail for one project: scoped analytics, running work, and
/// recent sessions. Opened by selecting a project on the Projects tab, the same
/// way a session row opens the session detail view. A session opened from here
/// leaves the project selected, so backing out of the session returns here.
struct ProjectDetailView: View {
    @EnvironmentObject private var state: AppState
    let project: Project

    @State private var copiedPath = false
    @State private var showingNewSession = false

    private var detail: AppState.ProjectDetail? { state.projectDetails[project.id] }
    private var running: [Session] { state.runningSessions(in: project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            navigationBar
            summary

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    runningSection

                    if let detail {
                        if let error = detail.error, detail.stats == nil {
                            NoticeRow(
                                icon: "exclamationmark.triangle.fill",
                                message: error,
                                tint: Theme.warn
                            )
                        } else if let stats = detail.stats {
                            SectionHeader("Trend")
                            UsageTrendCard(stats: stats, sessions: detail.sessions)

                            SectionHeader("Analytics")
                            ProjectStats(stats: stats)

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

                            ModelBreakdown(models: stats.models)
                        } else if detail.isLoading {
                            ProjectDetailSkeleton()
                                .shimmering()
                        }

                        filesSection

                        changesSection

                        if !detail.sessions.isEmpty {
                            SectionHeader("Recent sessions")
                            ProjectSessions(sessions: Array(detail.sessions.prefix(20)))
                        }
                    } else {
                        ProjectDetailSkeleton()
                            .shimmering()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .task(id: project.id) {
            async let detail: Void = state.loadProject(project.id)
            async let changes: Void = state.loadProjectChanges(project.id)
            async let files: Void = state.loadProjectFiles(project.id)
            _ = await (detail, changes, files)
        }
        .onExitCommand {
            state.closeProject()
        }
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet(directory: project.canonical)
                .environmentObject(state)
        }
    }

    // MARK: - Header

    private var navigationBar: some View {
        HStack(spacing: 8) {
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

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.displayName)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            Text(shortPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

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
                    Chip(
                        text: "\(Set(changes.map(\.displayPath)).count) files",
                        systemImage: "plus.forwardslash.minus",
                        tint: Theme.accent
                    )
                }

                Spacer(minLength: 4)

                actions
            }

            HStack(spacing: 10) {
                if let stats = detail?.stats {
                    Label("\(Fmt.grouped(stats.sessions)) sessions", systemImage: "bubble.left.and.bubble.right")
                    Label("\(Fmt.grouped(stats.steps)) steps", systemImage: "bolt.fill")
                }
                Label(Fmt.relative(from: project.lastActiveDate), systemImage: "clock")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
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
    /// they stay visible while the analytics below scroll.
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

    // MARK: - Changes

    @ViewBuilder
    private var changesSection: some View {
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
        }
    }

    // MARK: - Files

    @ViewBuilder
    private var filesSection: some View {
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
                .foregroundStyle(sessions.isEmpty ? .secondary : Theme.running)
        }

        if sessions.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Nothing running in this project.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 10)
        } else {
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
}

// MARK: - Scoped analytics

struct ProjectStats: View {
    let stats: Stats

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            StatTile(
                icon: "bolt.fill",
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
                caption: "\(Fmt.grouped(stats.sessions)) sessions"
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
                icon: "cpu",
                tint: Theme.reasoning,
                label: "Tokens",
                value: Fmt.compact(stats.tokens.generated),
                caption: "\(Fmt.compact(stats.tokens.cache.read)) cache read"
            )
            StatTile(
                icon: "flame.fill",
                tint: Theme.warn,
                label: "Streak",
                value: "\(stats.streak)",
                caption: "\(stats.activeDays) active days"
            )
        }
    }
}

// MARK: - Recent sessions

struct ProjectSessions: View {
    @EnvironmentObject var state: AppState
    let sessions: [Session]

    private var ordered: [Session] { SessionOrdering.mostRecentFirst(sessions) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ordered) { session in
                Button {
                    state.open(session)
                } label: {
                    ProjectSessionRow(session: session, running: false)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Show conversation and prompts")
                .transition(.recentInsertion)

                if session.id != ordered.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
        .card(padding: 10)
        .animateRecentInsertion(ids: ordered.map(\.id))
    }
}

struct ProjectSessionRow: View {
    let session: Session
    let running: Bool

    var body: some View {
        HStack(spacing: 6) {
            if running {
                PulsingDot(size: 5)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
            }

            Text(session.displayTitle)
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if running {
                Text(Fmt.elapsed(since: session.time.createdDate))
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(Theme.running)
            } else {
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Text(Fmt.relative(from: session.time.updatedDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
