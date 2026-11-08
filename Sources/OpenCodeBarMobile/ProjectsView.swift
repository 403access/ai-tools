import SwiftUI
import UIKit

struct ProjectsView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @State private var query = ProjectQuery()
    @State private var path = NavigationPath()
    @State private var limit = ProjectsView.pageSize

    private static let pageSize = 20

    private var runningCounts: [String: Int] {
        store.runningByProject.mapValues(\.count)
    }

    /// Projects after the search and filter chips have narrowed them. The page
    /// limit is applied when the rows are built, so counts describe the whole
    /// result set instead of the rows currently loaded.
    private var matchedProjects: [Project] {
        store.orderedProjects.applyingProjectQuery(query, runningCounts: runningCounts)
    }

    /// The search-only result, used to keep every filter chip's count useful
    /// while a chip is active.
    private var searchMatches: [Project] {
        store.orderedProjects.matchingProjectSearch(query.search)
    }

    var body: some View {
        let connection = store.connection
        let activeCount = store.activeCount

        return NavigationStack(path: $path) {
            Group {
                if !settings.isConfigured {
                    ScrollView {
                        SetupPrompt()
                            .padding(16)
                    }
                } else if store.isInitialLoading && store.orderedProjects.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("Projects")
                            SessionListSkeleton(count: 5)
                                .shimmering()
                        }
                        .padding(16)
                    }
                } else {
                    projectList
                }
            }
            .mobileScreenBackground()
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionPill(connection: connection, activeCount: activeCount)
                }
            }
            .searchable(
                text: $query.search,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Search name, path, Git, sandboxes"
            )
            .refreshable { await store.refreshLive() }
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(project: project)
            }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(
                    sessionID: session.id,
                    fallback: session,
                    onOpenSession: { path.append($0) }
                )
            }
            .task(id: store.lastUpdated) {
                openRequestedProject()
            }
        }
    }

    #if DEBUG
    /// Opens a project on launch for screenshot tooling:
    /// `SIMCTL_CHILD_OPENCODEBAR_OPEN_PROJECT=<id-or-path>`.
    private func openRequestedProject() {
        guard path.isEmpty,
              let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_OPEN_PROJECT"],
              let project = store.orderedProjects.first(where: {
                  $0.id == requested || $0.canonical == requested
              })
        else { return }
        path.append(project)
    }
    #else
    private func openRequestedProject() {}
    #endif

    private var projectList: some View {
        let projects = matchedProjects
        let visible = Array(projects.prefix(limit))
        let groups = ProjectGrouping.groups(
            for: visible,
            sort: query.sort,
            runningCounts: runningCounts
        )
        let ids = visible.map(\.id)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                SectionHeader("Projects") {
                    HStack(spacing: 6) {
                        if query.isFiltering {
                            Button("Clear") {
                                withAnimation(.easeInOut(duration: 0.16)) {
                                    query = ProjectQuery()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        }

                        Text(
                            projects.count == store.orderedProjects.count
                                ? "\(projects.count)"
                                : "\(projects.count) of \(store.orderedProjects.count)"
                        )
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                }

                controls

                if projects.isEmpty {
                    emptyState
                        .padding(.top, 8)
                } else {
                    ForEach(groups) { group in
                        groupHeader(group)
                        ForEach(group.projects) { project in
                            NavigationLink(value: project) {
                                ProjectRow(
                                    project: project,
                                    icon: store.projectIcons[project.id],
                                    running: store.runningSessions(in: project).count,
                                    lastActive: project.lastActiveDate,
                                    isLoading: store.refreshingProjectIcons.contains(project.id)
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.recentInsertion)
                        }
                    }

                    showMore(projects)

                    Text("\(projects.count) projects · \(sortSummary)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .animateRecentInsertion(ids: ids)
        .onChange(of: query) { _, _ in limit = Self.pageSize }
    }

    // MARK: - Search, sort, and filters

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sortMenu
                Spacer(minLength: 8)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProjectFilter.allCases) { filter in
                        filterChip(filter)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.vertical, 2)
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
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text(query.sort.shortTitle)
                    .font(.caption2.weight(.semibold))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
            .contentShape(Capsule())
        }
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
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(filter.shortTitle)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .opacity(count == 0 ? 0.45 : 1)
            }
            .font(.caption2.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(
                    isSelected ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.06)
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
        .accessibilityLabel("\(filter.title), \(count) projects")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var sortSummary: String {
        switch query.sort {
        case .recent: return "most recently active first"
        case .name: return "A–Z"
        case .running: return "running work first"
        }
    }

    private func groupHeader(_ group: ProjectGroup) -> some View {
        HStack(spacing: 5) {
            Text(group.title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text("\(group.projects.count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 1)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            EmptyState(
                icon: query.isFiltering ? "line.3.horizontal.decrease.circle" : "folder",
                title: store.orderedProjects.isEmpty ? "No projects yet" : "No projects match",
                subtitle: store.orderedProjects.isEmpty
                    ? "Projects appear after OpenCode has run in them."
                    : "Try another search, or clear the active filter."
            )

            if query.isFiltering && !store.orderedProjects.isEmpty {
                Button("Clear search and filters") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        query = ProjectQuery()
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
            }
        }
    }

    private func showMore(_ projects: [Project]) -> some View {
        Group {
            if projects.count > limit {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        limit += Self.pageSize
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                        Text("Show \(min(projects.count - limit, Self.pageSize)) more")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
    }
}

struct ProjectRow: View {
    let project: Project
    let icon: UIImage?
    let running: Int
    let lastActive: Date
    var isLoading = false

    var body: some View {
        HStack(spacing: 11) {
            ProjectIconTile(
                image: icon,
                running: running > 0,
                isLoading: isLoading,
                size: 34
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(project.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if running > 0 {
                        Text("\(running)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.running)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.running.opacity(0.14)))
                    }
                }
                Text(shortPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.relative(from: lastActive))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let vcs = project.vcs, !vcs.isEmpty {
                    Chip(text: vcs, tint: Theme.reasoning)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 12)
    }

    private var shortPath: String {
        (project.canonical as NSString).abbreviatingWithTildeInPath
    }
}
