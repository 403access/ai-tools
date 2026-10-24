import SwiftUI

// File changes written by a session. The patches come from OpenCode's
// edit/write tool metadata, so the text is the same diff the TUI shows.

struct ChangeSummaryBar: View {
    let changes: [FileChange]

    var body: some View {
        let additions = changes.reduce(0) { $0 + $1.additions }
        let deletions = changes.reduce(0) { $0 + $1.deletions }
        let files = Set(changes.map(\.displayPath)).count
        return HStack(spacing: 10) {
            Label(files == 1 ? "1 file" : "\(files) files", systemImage: "doc.on.doc")
                .foregroundStyle(.secondary)
            Text(verbatim: "+\(additions)").foregroundStyle(Theme.accent)
            Text(verbatim: "−\(deletions)").foregroundStyle(Theme.danger)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9, weight: .semibold).monospacedDigit())
        .card(padding: 9)
    }
}

struct FileChangeCard: View {
    let change: FileChange
    var defaultExpanded: Bool = false
    /// Lines shown before expanding. Zero keeps the card to just its header.
    var collapsedLines: Int = 16
    /// The tree layout already shows the path in its own row.
    var showsHeader: Bool = true

    @State private var expanded: Bool

    init(
        change: FileChange,
        defaultExpanded: Bool = false,
        collapsedLines: Int = 16,
        showsHeader: Bool = true
    ) {
        self.change = change
        self.defaultExpanded = defaultExpanded
        self.collapsedLines = collapsedLines
        self.showsHeader = showsHeader
        _expanded = State(initialValue: defaultExpanded)
    }

    private var lines: [String] { change.patchLines }
    private func visibleLines(from lines: [String]) -> [String] {
        if expanded { return lines }
        guard collapsedLines > 0 else { return [] }
        return Array(lines.prefix(collapsedLines))
    }

    var body: some View {
        let lines = self.lines
        let visibleLines = visibleLines(from: lines)
        return VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                HStack(spacing: 5) {
                    Image(systemName: change.statusIcon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(change.displayPath)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    Text(verbatim: "+\(change.additions)").foregroundStyle(Theme.accent)
                    Text(verbatim: "−\(change.deletions)").foregroundStyle(Theme.danger)
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
            }

            if lines.isEmpty {
                Text("No patch text was recorded for this change.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            } else {
                if !visibleLines.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                                patchLine(line)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                    )
                }

                if expanded || lines.count > max(collapsedLines, 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 7, weight: .bold))
                            Text(collapseLabel)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var collapseLabel: String {
        if expanded { return "Show less" }
        if collapsedLines == 0 { return "Show diff" }
        return "Show all \(lines.count) lines"
    }

    private var tint: Color {
        switch change.status {
        case "added": return Theme.accent
        case "deleted": return Theme.danger
        default: return Theme.running
        }
    }

    @ViewBuilder
    private func patchLine(_ line: String) -> some View {
        let added = line.hasPrefix("+") && !line.hasPrefix("+++")
        let removed = line.hasPrefix("-") && !line.hasPrefix("---")
        let header = line.hasPrefix("@@") || line.hasPrefix("Index:")

        Text(line.isEmpty ? " " : line)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(
                added ? Theme.accent
                    : removed ? Theme.danger
                    : header ? Theme.running
                    : Color.secondary
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                added ? Theme.accent.opacity(0.08)
                    : removed ? Theme.danger.opacity(0.08)
                    : Color.clear
            )
            .textSelection(.enabled)
            .fixedSize(horizontal: true, vertical: false)
    }
}

struct SessionChangesView: View {
    let changes: [FileChange]
    var showsSummary = true
    var expandFirst = true
    var collapsedLines = 16

    @State private var layout: Layout = .diffs
    @State private var expandedFolders: Set<String> = []
    @State private var expandedFiles: Set<String> = []

    private enum Layout {
        case diffs
        case tree

        var toggleIcon: String {
            self == .diffs ? "list.bullet.indent" : "list.bullet"
        }

        var toggleHelp: String {
            self == .diffs ? "Show file tree" : "Show diffs"
        }
    }

    private var groups: [FileChangeGroup] { FileChangeGroup.grouped(changes) }

    var body: some View {
        let groups = self.groups
        return VStack(alignment: .leading, spacing: 7) {
            if showsSummary {
                ChangeSummaryBar(changes: changes)
                    .overlay(alignment: .trailing) {
                        layoutButton(groups)
                            .padding(.trailing, 7)
                    }
            }

            if layout == .diffs {
                diffCards(groups)
            } else {
                treeRows(groups)
            }
        }
    }

    private func layoutButton(_ groups: [FileChangeGroup]) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if layout == .diffs {
                    // Start with the first level open so the tree reads as a
                    // hierarchy instead of a wall of closed folders.
                    if expandedFolders.isEmpty {
                        expandedFolders = FileChangeTree.topLevelDirectories(from: groups)
                    }
                    layout = .tree
                } else {
                    layout = .diffs
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
    }

    @ViewBuilder
    private func diffCards(_ groups: [FileChangeGroup]) -> some View {
        let groupCount = groups.count
        ForEach(groups) { group in
            VStack(alignment: .leading, spacing: 5) {
                if group.edits > 1 {
                    HStack(spacing: 4) {
                        Text(group.path)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Chip(text: "\(group.edits) edits")
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 1)
                }

                ForEach(Array(group.changes.enumerated()), id: \.element.id) { index, change in
                    FileChangeCard(
                        change: change,
                        defaultExpanded: expandFirst && groupCount <= 3 && index == 0,
                        collapsedLines: collapsedLines
                    )
                }
            }
        }
    }

    // MARK: - Tree

    private func treeRows(_ groups: [FileChangeGroup]) -> some View {
        let groupsByPath = Dictionary(uniqueKeysWithValues: groups.map { ($0.path, $0) })
        let rows = FileChangeTree.rows(from: groups, expanded: expandedFolders)
        return LazyVStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if row.node.isDirectory {
                    directoryRow(row.node, depth: row.depth)
                } else if let group = groupsByPath[row.node.path] {
                    treeFileRow(group, depth: row.depth)
                    if expandedFiles.contains(group.path) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(group.changes) { change in
                                FileChangeCard(
                                    change: change,
                                    defaultExpanded: true,
                                    collapsedLines: 12,
                                    showsHeader: false
                                )
                            }
                        }
                        .padding(.leading, CGFloat(row.depth + 1) * 12 + 14)
                        .padding(.vertical, 4)
                    }
                }
                if index != rows.count - 1 {
                    Divider().opacity(0.25)
                }
            }
        }
    }

    private func directoryRow(_ node: ProjectFileNode, depth: Int) -> some View {
        let isExpanded = expandedFolders.contains(node.path)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedFolders.remove(node.path)
                } else {
                    expandedFolders.insert(node.path)
                }
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

    private func treeFileRow(_ group: FileChangeGroup, depth: Int) -> some View {
        let isExpanded = expandedFiles.contains(group.path)
        let status = group.changes.first?.status
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if isExpanded {
                    expandedFiles.remove(group.path)
                } else {
                    expandedFiles.insert(group.path)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 8)
                Image(systemName: group.changes.first?.statusIcon ?? "doc.text")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint(for: status))
                    .frame(width: 12)
                Text(ProjectFile(path: group.path).name)
                    .font(.system(size: 9.5, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                if group.edits > 1 {
                    Text(verbatim: "\(group.edits)×")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: "+\(group.additions)").foregroundStyle(Theme.accent)
                Text(verbatim: "−\(group.deletions)").foregroundStyle(Theme.danger)
            }
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .padding(.leading, CGFloat(depth) * 12 + 14)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(group.path)
        .accessibilityLabel(group.path)
        .accessibilityHint(isExpanded ? "Hide diff" : "Show diff")
    }

    private func tint(for status: String?) -> Color {
        switch status {
        case "added": return Theme.accent
        case "deleted": return Theme.danger
        default: return Theme.running
        }
    }
}

struct ProjectChangesView: View {
    let changes: [FileChange]

    private struct SessionGroup: Identifiable {
        var id: String
        var title: String
        var changes: [FileChange]
    }

    private var groups: [SessionGroup] {
        var order: [String] = []
        var buckets: [String: [FileChange]] = [:]
        for change in changes {
            let id = change.sessionID ?? "unknown"
            if buckets[id] == nil { order.append(id) }
            buckets[id, default: []].append(change)
        }
        return order.map { id in
            let items = (buckets[id] ?? []).sorted { lhs, rhs in
                let left = lhs.created ?? 0
                let right = rhs.created ?? 0
                if left != right { return left > right }
                return lhs.id < rhs.id
            }
            return SessionGroup(
                id: id,
                title: items.first?.sessionTitle ?? "Session",
                changes: items
            )
        }
        .sorted { lhs, rhs in
            let left = lhs.changes.first?.created ?? 0
            let right = rhs.changes.first?.created ?? 0
            if left != right { return left > right }
            return lhs.id < rhs.id
        }
    }

    var body: some View {
        let groups = self.groups
        return VStack(alignment: .leading, spacing: 8) {
            ChangeSummaryBar(changes: changes)

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.running)
                        Text(group.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Set(group.changes.map(\.displayPath)).count)")
                            .font(.system(size: 9, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    SessionChangesView(
                        changes: group.changes,
                        showsSummary: false,
                        expandFirst: false,
                        collapsedLines: 0
                    )
                }
                .card(padding: 9)
            }
        }
    }
}
