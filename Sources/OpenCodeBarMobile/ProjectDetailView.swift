import SwiftUI
import UIKit

struct ProjectDetailView: View {
    @EnvironmentObject private var store: MobileStore
    let project: Project

    private var detail: MobileStore.ProjectDetail? { store.projectDetails[project.id] }
    private var running: [Session] { store.runningSessions(in: project) }

    var body: some View {
        // Capture this before building the toolbar: SwiftUI can evaluate
        // toolbar content in a hosting context that does not inherit the
        // screen's environment objects.
        let runningCount = running.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                runningSection

                if let detail {
                    if let error = detail.error, detail.stats == nil {
                        NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                    } else if let stats = detail.stats {
                        statsGrid(stats)

                        SectionHeader("Trend")
                        UsageTrendCard(stats: stats, sessions: detail.sessions)

                        if let totals = stats.tools.totals {
                            SectionHeader("Tool calls") {
                                if let rate = totals.successRate {
                                    Text("\(Int((rate * 100).rounded()))% success")
                                        .font(.caption2.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(
                                            rate >= 0.98 ? Theme.accent
                                                : rate >= 0.90 ? Theme.warn : Theme.danger
                                        )
                                }
                            }
                            ToolSummaryCard(totals: totals, mode: stats.tools.mode)

                            if let usage = stats.tools.usage, !usage.isEmpty {
                                SectionHeader("Tools") {
                                    Text("\(usage.count)")
                                        .font(.caption.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                ToolUsageBreakdown(usage: usage)
                            }
                        }

                        if !stats.models.isEmpty {
                            SectionHeader("Models")
                            ModelBreakdownCard(models: stats.models)
                        }
                    } else if detail.isLoading {
                        LoadingState(message: "Loading project…")
                    }

                    filesSection

                    changesSection

                    if !detail.sessions.isEmpty {
                        let sessions = Array(detail.sessions.prefix(40))
                        SectionHeader("Sessions") {
                            Text("\(detail.sessions.count)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                RecentSessionRow(session: session, project: project.displayName)
                            }
                            .buttonStyle(.plain)
                            .transition(.recentInsertion)
                        }
                        .animateRecentInsertion(ids: sessions.map(\.id))
                    }
                } else {
                    LoadingState(message: "Loading project…")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .mobileScreenBackground()
        .navigationTitle(project.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProjectRunningBadge(count: runningCount)
            }
        }
        .task(id: project.id) {
            async let detail = store.loadProject(project.id)
            async let changes = store.loadProjectChanges(project.id)
            async let files = store.loadProjectFiles(project.id)
            _ = await (detail, changes, files)
        }
        .refreshable {
            async let detail = store.loadProject(project.id, force: true)
            async let changes = store.loadProjectChanges(project.id, force: true)
            async let files = store.loadProjectFiles(project.id, force: true)
            _ = await (detail, changes, files)
            await store.refreshLive()
        }
    }

    @ViewBuilder
    private var changesSection: some View {
        let state = store.projectChanges[project.id]
        if let state, state.isLoading && state.changes.isEmpty {
            SectionHeader("Changes")
            LoadingState(message: "Collecting file changes…")
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
        }
    }

    @ViewBuilder
    private var filesSection: some View {
        let state = store.projectFiles[project.id]
        if let state, state.isLoading && state.files == nil {
            SectionHeader("Files")
            LoadingState(message: "Reading project folder…")
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

    private var summary: some View {
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

    private func statsGrid(_ stats: Stats) -> some View {
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
struct ModelBreakdownCard: View {
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
