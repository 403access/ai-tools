import SwiftUI

/// Per-project list: running work first, then the most recently active.
/// Selecting a project opens its detail page, mirroring the way a session row
/// opens the session detail view.
struct ProjectsTab: View {
    @EnvironmentObject var state: AppState
    @State private var limit = ProjectsTab.pageSize

    private static let pageSize = 20

    var body: some View {
        if state.projects.isEmpty {
            if state.isInitialLoading {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader("Projects")
                    SessionListSkeleton(count: 5)
                        .shimmering()
                }
            } else {
                EmptyState(
                    icon: "folder",
                    title: state.connection.isConnected ? "No projects yet" : state.connection.label,
                    subtitle: "Projects appear once OpenCode has run in a directory."
                )
            }
        } else {
            let projects = state.orderedProjects
            let visible = Array(projects.prefix(limit))
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(visible) { project in
                    Button {
                        state.open(project)
                    } label: {
                        ProjectRow(project: project)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Show \(project.displayName) analytics and sessions")
                    .transition(.recentInsertion)
                }

                if projects.count > limit {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            limit += Self.pageSize
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                            Text("Show \(min(projects.count - limit, Self.pageSize)) more")
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
                }
            }
            .animateRecentInsertion(ids: visible.map(\.id))
        }
    }
}

private struct ProjectRow: View {
    @EnvironmentObject var state: AppState
    let project: Project

    private var running: [Session] { state.runningSessions(in: project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
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
        }
        .card(padding: 10)
    }

    private var shortPath: String {
        (project.canonical as NSString).abbreviatingWithTildeInPath
    }
}
