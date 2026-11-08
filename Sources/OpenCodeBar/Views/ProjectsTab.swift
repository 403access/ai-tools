import SwiftUI

/// Per-project list: running work first, then the most recently active.
/// Selecting a project opens its detail page, mirroring the way a session row
/// opens the session detail view.
struct ProjectsTab: View {
    @EnvironmentObject var state: AppState
    @State private var limit = ProjectsTab.pageSize
    @State private var contentWidth: CGFloat = 0

    private static let pageSize = 20
    private static let cardWidth: CGFloat = 300
    private static let gridSpacing: CGFloat = 12
    /// Below this the list keeps the roomy single-column rows used by the
    /// tray panel and the split master column.
    private static let gridMinWidth: CGFloat = 700

    private var usesGrid: Bool { contentWidth >= Self.gridMinWidth }

    /// A single adaptive column definition lets SwiftUI derive the number of
    /// fixed-width cards from the width it is actually given. Computing the
    /// count from a measured width made the scroll content keep its old width
    /// while the window shrank, so cards spilled past the trailing edge.
    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: Self.cardWidth, maximum: Self.cardWidth),
                spacing: Self.gridSpacing
            )
        ]
    }

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

            VStack(alignment: .leading, spacing: 12) {
                if usesGrid {
                    LazyVGrid(
                        columns: gridColumns,
                        alignment: .leading,
                        spacing: Self.gridSpacing
                    ) {
                        projectLinks(visible)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        projectLinks(visible)
                    }
                }

                showMore(projects)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ProjectsWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(ProjectsWidthKey.self) { contentWidth = $0 }
            .animateRecentInsertion(ids: visible.map(\.id))
        }
    }

    @ViewBuilder
    private func projectLinks(_ visible: [Project]) -> some View {
        ForEach(visible) { project in
            Button {
                state.open(project)
            } label: {
                if usesGrid {
                    ProjectGridCard(project: project)
                } else {
                    ProjectRow(project: project)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Show \(project.displayName) analytics and sessions")
            .transition(.recentInsertion)
        }
    }

    @ViewBuilder
    private func showMore(_ projects: [Project]) -> some View {
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
            .frame(width: usesGrid ? Self.cardWidth : nil)
            .help("Load more projects")
        }
    }
}

private struct ProjectRow: View {
    @EnvironmentObject var state: AppState
    let project: Project

    private var running: [Session] { state.runningSessions(in: project) }

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            ProjectIconView(
                image: state.projectIcons[project.id],
                running: !running.isEmpty,
                size: 30
            )

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
        }
        .card(padding: 10)
    }

    private var shortPath: String {
        (project.canonical as NSString).abbreviatingWithTildeInPath
    }
}

/// Fixed-width project card used by the desktop grid. The row layout stays for
/// the tray panel and the split master column, where 300 pt cards would waste
/// more space than they save.
private struct ProjectGridCard: View {
    @EnvironmentObject var state: AppState
    let project: Project

    private var running: [Session] { state.runningSessions(in: project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                ProjectIconView(
                    image: state.projectIcons[project.id],
                    running: !running.isEmpty,
                    size: 34
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(project.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(shortPath)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 2)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 5) {
                if running.isEmpty {
                    Text(Fmt.relative(from: project.lastActiveDate))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    PulsingDot(size: 5)
                    Text("\(running.count) running")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.running)
                }

                Spacer(minLength: 4)

                if let vcs = project.vcs, !vcs.isEmpty {
                    Chip(text: vcs, tint: Theme.reasoning)
                }
                if !project.sandboxes.isEmpty {
                    Chip(text: "\(project.sandboxes.count) sandbox", systemImage: "shippingbox.fill")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .card(padding: 10)
    }

    private var shortPath: String {
        (project.canonical as NSString).abbreviatingWithTildeInPath
    }
}

/// Width of the project collection, used to decide between rows and the fixed
/// width card grid.
private struct ProjectsWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
