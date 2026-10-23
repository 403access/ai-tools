import SwiftUI

/// Browses every file in a project folder. Git working-tree changes are marked
/// inline, and the All / Changed switch narrows the list without a second
/// request. The layout button swaps the flat list for a collapsible tree.
struct ProjectFilesView: View {
    let files: ProjectFiles
    var onRefresh: (() -> Void)?

    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var layout: Layout = .list
    @State private var expanded: Set<String> = []

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case changed = "Changed"

        var id: String { rawValue }
    }

    private enum Layout {
        case list
        case tree

        var toggleIcon: String {
            self == .list ? "list.bullet.indent" : "list.bullet"
        }

        var toggleHelp: String {
            self == .list ? "Show tree" : "Show list"
        }
    }

    private struct TreeRow: Identifiable {
        let node: ProjectFileNode
        let depth: Int

        var id: String { node.id }
    }

    /// Computed once per body below; the previous computed property was read
    /// three times (empty check, count and the list), so a 20k-file project paid
    /// the full scan three times on every keystroke.
    private func visibleFiles() -> [ProjectFile] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = files.files
        guard !needle.isEmpty else {
            guard filter == .changed else { return source }
            return source.filter(\.isChanged)
        }
        return source.filter { file in
            if filter == .changed && !file.isChanged { return false }
            return file.path.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        let visible = visibleFiles()
        return VStack(alignment: .leading, spacing: 7) {
            controls
            searchField

            if files.vcs == nil {
                Text("This folder is not a git work tree, so change status is unavailable.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if visible.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(emptyLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else if layout == .list {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, file in
                        fileRow(file)
                        if index != visible.count - 1 {
                            Divider().opacity(0.25)
                        }
                    }
                }
            } else {
                treeRowsContent(for: visible)
            }

            if files.truncated {
                Text("Showing the first \(files.files.count) of \(files.total) files.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warn)
            }
        }
        .card(padding: 9)
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Picker("Files", selection: $filter) {
                ForEach(Filter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 128)

            Text("\(files.total) files · \(files.changed) changed")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if layout == .list {
                        // Start with the first level open so the tree reads as a
                        // hierarchy instead of a wall of closed folders.
                        if expanded.isEmpty {
                            expanded = Set(files.files.compactMap { $0.ancestorDirectories.first })
                        }
                        layout = .tree
                    } else {
                        layout = .list
                    }
                }
            } label: {
                Image(systemName: layout.toggleIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(layout.toggleHelp)
            .accessibilityLabel(layout.toggleHelp)

            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reload files")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter files", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private var emptyLabel: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No files match “\(query)”."
        }
        if filter == .changed {
            return files.vcs == nil ? "Change status needs a git repository." : "No changed files."
        }
        return "No files found."
    }

    // MARK: - Tree

    private func treeRowsContent(for visible: [ProjectFile]) -> some View {
        let expanded = effectiveExpanded(for: visible)
        let rows = flattened(ProjectFileTree.nodes(from: visible), expanded: expanded)
        return LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if row.node.isDirectory {
                    directoryRow(row.node, depth: row.depth, isExpanded: expanded.contains(row.node.path))
                } else if let file = row.node.file {
                    treeFileRow(file, depth: row.depth)
                }
                if index != rows.count - 1 {
                    Divider().opacity(0.25)
                }
            }
        }
    }

    /// Search hits stay visible even when their folders were collapsed before
    /// the query was typed, so a match is never hidden inside a closed folder.
    private func effectiveExpanded(for visible: [ProjectFile]) -> Set<String> {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return expanded
        }
        var paths = expanded
        for file in visible {
            paths.formUnion(file.ancestorDirectories)
        }
        return paths
    }

    private func flattened(
        _ nodes: [ProjectFileNode],
        expanded: Set<String>,
        depth: Int = 0
    ) -> [TreeRow] {
        var rows: [TreeRow] = []
        for node in nodes {
            rows.append(TreeRow(node: node, depth: depth))
            if node.isDirectory, expanded.contains(node.path) {
                rows.append(contentsOf: flattened(node.children, expanded: expanded, depth: depth + 1))
            }
        }
        return rows
    }

    private func toggleExpansion(_ path: String) {
        if expanded.contains(path) {
            expanded.remove(path)
        } else {
            expanded.insert(path)
        }
    }

    private func directoryRow(
        _ node: ProjectFileNode,
        depth: Int,
        isExpanded: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                toggleExpansion(node.path)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 9)
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .frame(width: 12)
                Text(node.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if node.changedCount > 0 {
                    Text("\(node.changedCount) changed")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.warn.opacity(0.12)))
                }
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(node.path)
        .accessibilityLabel(node.name)
        .accessibilityHint(isExpanded ? "Collapse folder" : "Expand folder")
    }

    private func treeFileRow(_ file: ProjectFile, depth: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: file.statusIcon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint(for: file))
                .frame(width: 12)

            Text(file.name)
                .font(.system(size: 9.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 4)

            if file.isChanged {
                Text(file.statusLabel)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint(for: file))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tint(for: file).opacity(0.12)))
            }
        }
        .padding(.leading, CGFloat(depth) * 12 + 14)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(file.path)
    }

    private func fileRow(_ file: ProjectFile) -> some View {
        HStack(spacing: 6) {
            Image(systemName: file.statusIcon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint(for: file))
                .frame(width: 12)

            (Text(file.directory).foregroundColor(.secondary) + Text(file.name))
                .font(.system(size: 9.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 4)

            if file.isChanged {
                Text(file.statusLabel)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint(for: file))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tint(for: file).opacity(0.12)))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(file.path)
    }

    private func tint(for file: ProjectFile) -> Color {
        switch file.status {
        case "added": return Theme.accent
        case "deleted": return Theme.danger
        case "renamed": return Theme.reasoning
        case "modified": return Theme.warn
        default: return .secondary
        }
    }
}
