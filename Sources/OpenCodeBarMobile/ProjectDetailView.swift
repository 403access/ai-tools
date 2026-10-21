import SwiftUI
import UIKit

struct ProjectDetailView: View {
    @EnvironmentObject private var store: MobileStore
    let project: Project

    private var detail: MobileStore.ProjectDetail? { store.projectDetails[project.id] }
    private var running: [Session] { store.runningSessions(in: project) }

    var body: some View {
        ScrollView {
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

                        if !stats.models.isEmpty {
                            SectionHeader("Models")
                            ModelBreakdownCard(models: stats.models)
                        }
                    } else if detail.isLoading {
                        LoadingState(message: "Loading project…")
                    }

                    if !detail.sessions.isEmpty {
                        SectionHeader("Sessions") {
                            Text("\(detail.sessions.count)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(detail.sessions.prefix(40))) { session in
                            NavigationLink(value: session) {
                                RecentSessionRow(session: session, project: project.displayName)
                            }
                            .buttonStyle(.plain)
                        }
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
                if running.isEmpty {
                    Chip(text: "Idle")
                } else {
                    HStack(spacing: 5) {
                        PulsingDot(size: 6)
                        Text("\(running.count) running")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.running)
                    }
                }
            }
        }
        .task(id: project.id) {
            await store.loadProject(project.id)
        }
        .refreshable {
            await store.loadProject(project.id, force: true)
            await store.refreshLive()
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
                Chip(text: "Active \(Fmt.relative(from: project.lastActiveDate))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 13)
    }

    @ViewBuilder
    private var runningSection: some View {
        if !running.isEmpty {
            SectionHeader("Running") {
                Text("\(running.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.running)
            }
            ForEach(running) { session in
                NavigationLink(value: session) {
                    RunningSessionRow(
                        session: session,
                        project: project.displayName,
                        activity: store.activity(for: session.id),
                        subagents: store.activeSubagentCount(for: session.id)
                    )
                }
                .buttonStyle(.plain)
            }
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
                caption: "\(stats.sessions) sessions"
            )
            StatTile(
                icon: "dollarsign.circle.fill",
                tint: Theme.accent,
                label: "Cost",
                value: Fmt.usd(stats.cost),
                caption: "\(Fmt.compact(stats.tokens.generated)) tokens"
            )
            StatTile(
                icon: "flame.fill",
                tint: Theme.warn,
                label: "Streak",
                value: "\(stats.streak)",
                caption: "\(stats.activeDays) active days"
            )
            StatTile(
                icon: "bubble.left.and.bubble.right.fill",
                tint: Theme.input,
                label: "Prompts",
                value: Fmt.grouped(stats.prompts),
                caption: "\(stats.subagents) subagents"
            )
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
