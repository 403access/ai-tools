import AppKit
import SwiftUI

/// A full project browser for the New Session flow. The old menu picker could
/// only walk the list in one order; this view lets someone search by name or
/// path, choose a sort, and narrow the list to running, Git, or sandboxed
/// projects before starting a session.
struct ProjectPickerSheet: View {
    let projects: [Project]
    let icons: [String: NSImage]
    let runningCounts: [String: Int]
    let selection: String?
    let onSelect: (Project) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var query = ProjectQuery()
    @State private var hoveredID: String?
    @State private var focusedID: String?
    @FocusState private var searchFocused: Bool

    private var searchMatches: [Project] {
        projects.matchingProjectSearch(query.search)
    }

    private var visible: [Project] {
        projects.applyingProjectQuery(query, runningCounts: runningCounts)
    }

    private var groups: [ProjectGroup] {
        ProjectGrouping.groups(for: visible, sort: query.sort, runningCounts: runningCounts)
    }

    private var selectedProject: Project? {
        guard let selection else { return nil }
        return projects.first { $0.canonical == selection }
    }

    private var isFiltering: Bool {
        query.filter != .all || !query.trimmedSearch.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            searchField
            filterControls
            Divider().opacity(0.35)
            results
            footer
        }
        .padding(15)
        .frame(width: 500, height: 570)
        .onAppear {
            focusedID = selectedProject?.id ?? visible.first?.id
            searchFocused = true
        }
        .onChange(of: visible.map(\.id)) { _, ids in
            if let focusedID, ids.contains(focusedID) { return }
            focusedID = ids.first
        }
        .onKeyPress(.downArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress("f", phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            searchFocused = true
            return .handled
        }
        .onExitCommand { dismiss() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose a project")
                    .font(.system(size: 15, weight: .semibold))
                Text("Search by name or path, then sort and filter to find the right folder.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let selectedProject {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text(selectedProject.displayName)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                .help("This project is currently selected")
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close without changing the project")
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.accent : Color.secondary.opacity(0.7))

            TextField("Search projects, paths, Git, or sandboxes", text: $query.search)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($searchFocused)
                .onSubmit { chooseFocused() }

            if !query.search.isEmpty {
                Button {
                    query.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            Text("⌘F")
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .opacity(searchFocused ? 0 : 1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    searchFocused ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        )
        .animation(.easeOut(duration: 0.14), value: searchFocused)
    }

    // MARK: - Sort and filters

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("SORT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Picker("Sort projects", selection: $query.sort) {
                    ForEach(ProjectSortOrder.allCases) { option in
                        Text(option.shortTitle).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 205)
                .help(query.sort.help)

                Spacer(minLength: 0)

                Text("\(visible.count) of \(projects.count)")
                    .font(.system(size: 9.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
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
                    .font(.system(size: 8.5, weight: .bold))
                Text(filter.shortTitle)
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 8.5, weight: .semibold))
                    .monospacedDigit()
                    .opacity(count == 0 ? 0.45 : 1)
            }
            .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            .background(
                Capsule().fill(
                    isSelected ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.05)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(filter.title), \(count) projects")
    }

    // MARK: - Results

    @ViewBuilder
    private var results: some View {
        if visible.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(groups) { group in
                            groupHeader(group)
                            ForEach(group.projects) { project in
                                projectRow(project)
                                    .id(project.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: focusedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
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
            Spacer()
        }
        .padding(.horizontal, 5)
        .padding(.top, 7)
        .padding(.bottom, 1)
    }

    private func projectRow(_ project: Project) -> some View {
        let isSelected = project.canonical == selection
        let isFocused = focusedID == project.id
        let isHovered = hoveredID == project.id
        let running = runningCounts[project.id] ?? 0
        let path = (project.canonical as NSString).abbreviatingWithTildeInPath

        return Button {
            choose(project)
        } label: {
            HStack(spacing: 10) {
                ProjectIconView(
                    image: icons[project.id],
                    running: running > 0,
                    size: 30
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(project.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }

                        if running > 0 {
                            HStack(spacing: 4) {
                                PulsingDot(size: 4)
                                Text("\(running)")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(Theme.running)
                        }

                        Spacer(minLength: 5)

                        Text(Fmt.relative(from: project.lastActiveDate))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 5) {
                        Text(path)
                            .font(.system(size: 9, design: .monospaced))
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
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowFill(isSelected: isSelected, isFocused: isFocused, isHovered: isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Theme.accent.opacity(0.35)
                            : (isFocused ? Theme.accent.opacity(0.16) : Color.clear),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Start a session in \(project.displayName)")
        .onHover { inside in
            if inside {
                hoveredID = project.id
                focusedID = project.id
            } else if hoveredID == project.id {
                hoveredID = nil
            }
        }
        .accessibilityLabel("\(project.displayName), \(path)")
        .accessibilityValue(isSelected ? "Selected" : "")
    }

    private func rowFill(isSelected: Bool, isFocused: Bool, isHovered: Bool) -> Color {
        if isSelected { return Theme.accent.opacity(0.10) }
        if isHovered { return Color.primary.opacity(0.065) }
        if isFocused { return Color.primary.opacity(0.035) }
        return .clear
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: isFiltering ? "line.3.horizontal.decrease.circle" : "folder")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.tertiary)
            Text(projects.isEmpty ? "No projects yet" : "No projects match")
                .font(.system(size: 12, weight: .medium))
            Text(
                projects.isEmpty
                    ? "Projects appear once OpenCode has run in a folder."
                    : "Try a different search, or clear the active filter."
            )
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if isFiltering && !projects.isEmpty {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 24)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("\(visible.count) of \(projects.count) projects")
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            let running = visible.reduce(0) { $0 + (runningCounts[$1.id] ?? 0) }
            if running > 0 {
                Text("· \(running) running")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.running)
            }

            Spacer()

            Text("↑↓ move · ↩ choose · esc close")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Actions

    private func choose(_ project: Project) {
        onSelect(project)
        dismiss()
    }

    private func chooseFocused() {
        guard let focusedID,
              let project = visible.first(where: { $0.id == focusedID }) ?? visible.first
        else { return }
        choose(project)
    }

    private func moveFocus(by offset: Int) {
        let ids = visible.map(\.id)
        guard !ids.isEmpty else { return }
        guard let focusedID,
              let index = ids.firstIndex(of: focusedID)
        else {
            self.focusedID = offset > 0 ? ids.first : ids.last
            return
        }
        let next = (index + offset).clamped(to: 0...(ids.count - 1))
        self.focusedID = ids[next]
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
