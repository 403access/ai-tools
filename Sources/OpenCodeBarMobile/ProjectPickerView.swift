import SwiftUI

/// The mobile project browser behind the New Session sheet. It replaces the
/// one-way dropdown with a searchable screen where projects can be sorted and
/// narrowed to running work, Git checkouts, or sandboxed projects.
struct MobileProjectPickerView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let selectedDirectory: String
    let onSelect: (Project) -> Void

    @State private var query = ProjectQuery()

    private var runningCounts: [String: Int] {
        store.runningByProject.mapValues(\.count)
    }

    private var searchMatches: [Project] {
        store.orderedProjects.matchingProjectSearch(query.search)
    }

    private var visible: [Project] {
        store.orderedProjects.applyingProjectQuery(query, runningCounts: runningCounts)
    }

    private var groups: [ProjectGroup] {
        ProjectGrouping.groups(
            for: visible,
            sort: query.sort,
            runningCounts: runningCounts
        )
    }

    private var selectedProject: Project? {
        store.orderedProjects.first { $0.canonical == selectedDirectory }
    }

    private var isFiltering: Bool {
        query.filter != .all || !query.trimmedSearch.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            controls

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 9) {
                    if visible.isEmpty {
                        emptyState
                            .padding(.top, 28)
                    } else {
                        ForEach(groups) { group in
                            groupHeader(group)
                            ForEach(group.projects) { project in
                                projectRow(project)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .animation(.easeInOut(duration: 0.18), value: query)
        }
        .mobileScreenBackground()
        .navigationTitle("Choose project")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query.search,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search name, path, Git, sandboxes"
        )
        .toolbar {
            if let selectedProject {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        choose(selectedProject)
                    } label: {
                        Text("Keep")
                            .font(.footnote.weight(.semibold))
                    }
                    .accessibilityLabel("Keep \(selectedProject.displayName)")
                }
            }
        }
        .onAppear {
            store.loadProjectIcons(for: store.orderedProjects)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                sortMenu

                Spacer(minLength: 8)

                Text("\(visible.count) of \(store.orderedProjects.count)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 9)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MobileTheme.border)
                .frame(height: 0.5)
        }
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

    // MARK: - Results

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

    private func projectRow(_ project: Project) -> some View {
        let isSelected = project.canonical == selectedDirectory
        let running = runningCounts[project.id] ?? 0
        let path = (project.canonical as NSString).abbreviatingWithTildeInPath

        return Button {
            choose(project)
        } label: {
            HStack(spacing: 11) {
                ProjectIconTile(
                    image: store.projectIcons[project.id],
                    running: running > 0,
                    isLoading: store.refreshingProjectIcons.contains(project.id),
                    size: 34
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(project.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.accent)
                        }

                        if running > 0 {
                            HStack(spacing: 3) {
                                PulsingDot(size: 4)
                                Text("\(running)")
                                    .font(.caption2.weight(.bold))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(Theme.running)
                        }
                    }

                    HStack(spacing: 5) {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let vcs = project.vcs, !vcs.isEmpty {
                            Chip(text: vcs, tint: Theme.reasoning)
                        }
                        if !project.sandboxes.isEmpty {
                            Chip(
                                text: "\(project.sandboxes.count)",
                                systemImage: "shippingbox.fill",
                                tint: Theme.cacheRead
                            )
                        }
                    }
                }

                Spacer(minLength: 4)

                Text(Fmt.relative(from: project.lastActiveDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Image(systemName: isSelected ? "checkmark" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Theme.accent : Color.secondary.opacity(0.55))
            }
            .card(padding: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent.opacity(0.4) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(project.displayName), \(path)")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityHint("Starts a new session in this project")
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle" : "folder")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(store.orderedProjects.isEmpty ? "No projects yet" : "No projects match")
                .font(.subheadline.weight(.medium))
            Text(
                store.orderedProjects.isEmpty
                    ? "Projects appear once OpenCode has run in a folder."
                    : "Try another search, or clear the active filter."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if isFiltering && !store.orderedProjects.isEmpty {
                Button("Clear search and filters") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        query = ProjectQuery()
                    }
                }
                .font(.footnote.weight(.semibold))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }

    private func choose(_ project: Project) {
        onSelect(project)
        dismiss()
    }
}
