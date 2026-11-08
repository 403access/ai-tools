import SwiftUI

/// Per-project list: running work first, then the most recently active.
/// Selecting a project opens its detail page, mirroring the way a session row
/// opens the session detail view.
struct ProjectsTab: View {
    @EnvironmentObject var state: AppState
    @State private var query = ProjectQuery()
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

    /// Running session counts keyed by project id, shared by filtering and
    /// sorting so both agree on which projects are "running now".
    private var runningCounts: [String: Int] {
        state.runningByProject.mapValues(\.count)
    }

    /// Projects after the search and filter chips have narrowed them. The page
    /// limit is applied later so the counts describe the whole result set
    /// rather than the cards currently on screen.
    private var matchedProjects: [Project] {
        state.orderedProjects.applyingProjectQuery(query, runningCounts: runningCounts)
    }

    /// The search-only result, used to keep every filter chip's count useful
    /// while a chip is active.
    private var searchMatches: [Project] {
        state.orderedProjects.matchingProjectSearch(query.search)
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
            let projects = matchedProjects
            let visible = Array(projects.prefix(limit))
            let groups = ProjectGrouping.groups(
                for: visible,
                sort: query.sort,
                runningCounts: runningCounts
            )

            VStack(alignment: .leading, spacing: 10) {
                controls(total: state.orderedProjects.count, shown: projects.count)

                if projects.isEmpty {
                    filteredEmptyState
                } else {
                    if usesGrid {
                        LazyVGrid(
                            columns: gridColumns,
                            alignment: .leading,
                            spacing: Self.gridSpacing
                        ) {
                            ForEach(groups) { group in
                                Section {
                                    ForEach(group.projects) { project in
                                        projectButton(project)
                                    }
                                } header: {
                                    groupHeader(group)
                                }
                            }
                        }
                    } else {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(groups) { group in
                                groupHeader(group)
                                ForEach(group.projects) { project in
                                    projectButton(project)
                                }
                            }
                        }
                    }

                    showMore(projects)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ProjectsWidthKey.self, value: proxy.size.width)
                }
            )
            .onPreferenceChange(ProjectsWidthKey.self) { contentWidth = $0 }
            .animateRecentInsertion(ids: visible.map(\.id))
            .onChange(of: query) { _, _ in limit = Self.pageSize }
        }
    }

    // MARK: - Search, sort, and filters

    private func controls(total: Int, shown: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Projects") {
                HStack(spacing: 6) {
                    if query.isFiltering {
                        Button("Clear") {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                query = ProjectQuery()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .help("Clear the search and filters")
                    }

                    Text(shown == total ? "\(total)" : "\(shown) of \(total)")
                        .font(.system(size: 9, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 6) {
                searchField
                sortMenu
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(ProjectFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    query.trimmedSearch.isEmpty ? Color.secondary.opacity(0.7) : Theme.accent
                )

            TextField("Search projects or paths", text: $query.search)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))

            if !query.search.isEmpty {
                Button {
                    query.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    query.trimmedSearch.isEmpty
                        ? Color.primary.opacity(0.05)
                        : Theme.accent.opacity(0.35),
                    lineWidth: 1
                )
        )
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ProjectSortOrder.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        query.sort = option
                    }
                } label: {
                    if option == query.sort {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Label(option.title, systemImage: option.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 8, weight: .bold))
                Text(query.sort.shortTitle)
                    .font(.system(size: 9, weight: .semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.accent)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(query.sort.help)
        .accessibilityLabel("Sort projects")
        .accessibilityValue(query.sort.title)
    }

    private func filterChip(_ filter: ProjectFilter) -> some View {
        let isSelected = query.filter == filter
        let count = searchMatches.filter {
            filter.matches($0, runningCounts: runningCounts)
        }.count

        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                query.filter = isSelected && filter != .all ? .all : filter
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: filter.icon)
                    .font(.system(size: 8, weight: .bold))
                Text(filter.shortTitle)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 8, weight: .semibold))
                    .monospacedDigit()
                    .opacity(count == 0 ? 0.45 : 1)
            }
            .font(.system(size: 9, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .background(
                Capsule().fill(
                    isSelected
                        ? Theme.accent.opacity(0.16)
                        : Color.primary.opacity(0.05)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? Theme.accent.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(filter.title)
        .accessibilityLabel("\(filter.title), \(count) projects")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func groupHeader(_ group: ProjectGroup) -> some View {
        HStack(spacing: 5) {
            Text(group.title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("\(group.projects.count)")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private func projectButton(_ project: Project) -> some View {
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

    private var filteredEmptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No projects match")
                .font(.system(size: 12, weight: .medium))
            Text("Try a different search, sort, or filter.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Clear search and filters") {
                withAnimation(.easeInOut(duration: 0.16)) {
                    query = ProjectQuery()
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
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
