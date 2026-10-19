import SwiftUI

/// Per-project view: what is running right now, recent history, and analytics
/// scoped to that project. Projects are collapsed by default; expanding one
/// loads its scoped stats and recent sessions on demand.
struct ProjectsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.projects.isEmpty {
            EmptyState(
                icon: "folder",
                title: state.connection.isConnected ? "No projects yet" : state.connection.label,
                subtitle: "Projects appear once OpenCode has run in a directory."
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(state.orderedProjects) { project in
                    ProjectCard(project: project, expanded: state.expandedProjectID == project.id)
                }
            }
        }
    }
}

private struct ProjectCard: View {
    @EnvironmentObject var state: AppState
    let project: Project
    let expanded: Bool

    private var running: [Session] { state.runningSessions(in: project) }
    private var detail: AppState.ProjectDetail? { state.projectDetails[project.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                state.toggleProject(project.id)
            } label: {
                header
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help(project.canonical)

            if expanded {
                Divider().opacity(0.4).padding(.vertical, 8)
                expandedBody
            }
        }
        .card(padding: 10)
    }

    // MARK: - Collapsed header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 8)

                Text(project.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 4)

                if !running.isEmpty {
                    HStack(spacing: 4) {
                        PulsingDot(size: 5)
                        Text("\(running.count)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.running)
                    }
                }

                Text(Fmt.relative(from: project.lastActiveDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                Text(shortPath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let vcs = project.vcs, !vcs.isEmpty {
                    Chip(text: vcs, tint: Theme.reasoning)
                }
                if !project.sandboxes.isEmpty {
                    Chip(text: "\(project.sandboxes.count) sandbox", systemImage: "shippingbox.fill")
                }
            }
            .padding(.leading, 14)
        }
    }

    private var shortPath: String {
        (project.canonical as NSString).abbreviatingWithTildeInPath
    }

    // MARK: - Expanded content

    @ViewBuilder
    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            runningSection

            if let detail {
                if let error = detail.error, detail.stats == nil {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                }
                if let stats = detail.stats {
                    SectionHeader("Analytics")
                    ProjectStats(stats: stats)
                    ModelBreakdown(models: stats.models)
                }
                if !detail.sessions.isEmpty {
                    SectionHeader("Recent sessions")
                    ProjectSessions(sessions: detail.sessions)
                }
                if detail.isLoading && detail.stats == nil {
                    LoadingState(message: "Loading project…")
                }
            } else {
                LoadingState(message: "Loading project…")
            }
        }
    }

    @ViewBuilder
    private var runningSection: some View {
        SectionHeader("Running") {
            Text("\(running.count)")
                .font(.system(size: 10, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(running.isEmpty ? .secondary : Theme.running)
        }

        if running.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Nothing running in this project.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ForEach(running) { session in
                Button {
                    state.open(session)
                } label: {
                    ProjectSessionRow(session: session, running: true)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
    }
}

private struct ProjectStats: View {
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

private struct ProjectSessions: View {
    @EnvironmentObject var state: AppState
    let sessions: [Session]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sessions) { session in
                Button {
                    state.open(session)
                } label: {
                    ProjectSessionRow(session: session, running: false)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                if session.id != sessions.last?.id {
                    Divider().opacity(0.35)
                }
            }
        }
    }
}

private struct ProjectSessionRow: View {
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
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
