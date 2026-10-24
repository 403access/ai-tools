import SwiftUI

// File changes written by a session. Patches come from OpenCode's edit/write
// tool metadata, so the text here is the same diff the TUI shows.

struct ChangeSummaryBar: View {
    let changes: [FileChange]

    var body: some View {
        let additions = changes.reduce(0) { $0 + $1.additions }
        let deletions = changes.reduce(0) { $0 + $1.deletions }
        let files = Set(changes.map(\.displayPath)).count
        return HStack(spacing: 12) {
            Label(
                files == 1 ? "1 file" : "\(files) files",
                systemImage: "doc.on.doc"
            )
            .foregroundStyle(.secondary)

            Text(verbatim: "+\(additions)")
                .foregroundStyle(Theme.accent)
            Text(verbatim: "−\(deletions)")
                .foregroundStyle(Theme.danger)

            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold).monospacedDigit())
        .card(padding: 11)
    }
}

/// A single file's patch. Repeated edits to the same file are grouped by the
/// caller; each card can collapse a long diff to its first lines.
struct FileChangeCard: View {
    let change: FileChange
    var defaultExpanded: Bool = false
    /// Lines shown before expanding. Zero keeps the card to just its header.
    var collapsedLines: Int = 18
    /// The tree layout already shows the path in its own row.
    var showsHeader: Bool = true

    @State private var expanded: Bool

    init(
        change: FileChange,
        defaultExpanded: Bool = false,
        collapsedLines: Int = 18,
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
        return VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                HStack(spacing: 6) {
                    Image(systemName: change.statusIcon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(change.displayPath)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 4)
                    Text(verbatim: "+\(change.additions)")
                        .foregroundStyle(Theme.accent)
                    Text(verbatim: "−\(change.deletions)")
                        .foregroundStyle(Theme.danger)
                }
                .font(.caption2.weight(.semibold).monospacedDigit())
            }

            if lines.isEmpty {
                Text("No patch text was recorded for this change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !visibleLines.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                                patchLine(line)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.035))
                    )
                }

                if expanded || lines.count > max(collapsedLines, 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                            Text(collapseLabel)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
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
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(
                added ? Theme.accent
                    : removed ? Theme.danger
                    : header ? Theme.running
                    : Color.secondary
            )
            .padding(.horizontal, 7)
            .padding(.vertical, 1)
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

/// Groups edits by file, showing the newest edit first.
struct SessionChangesView: View, Equatable {
    let changes: [FileChange]
    var showsSummary = true
    var expandFirst = true
    var collapsedLines = 18

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

    /// Layout and expansion are view-local; parent equality only depends on the
    /// data it passes in, so opening a folder never forces a full republish.
    static func == (lhs: SessionChangesView, rhs: SessionChangesView) -> Bool {
        lhs.changes == rhs.changes
            && lhs.showsSummary == rhs.showsSummary
            && lhs.expandFirst == rhs.expandFirst
            && lhs.collapsedLines == rhs.collapsedLines
    }

    var body: some View {
        let groups = self.groups
        return VStack(alignment: .leading, spacing: 9) {
            if showsSummary {
                ChangeSummaryBar(changes: changes)
                    .overlay(alignment: .trailing) {
                        layoutButton(groups)
                            .padding(.trailing, 9)
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
                .font(.caption.weight(.semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(layout.toggleHelp)
    }

    /// A busy session can write thousands of patches. Build file cards lazily so
    /// opening the Changes tab only pays for what is on screen; an eager stack
    /// made that switch block the main thread for seconds.
    private func diffCards(_ groups: [FileChangeGroup]) -> some View {
        let groupCount = groups.count
        return LazyVStack(alignment: .leading, spacing: 9) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    if group.edits > 1 {
                        HStack(spacing: 5) {
                            Text(group.path)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Chip(text: "\(group.edits) edits")
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)
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
    }

    // MARK: - Tree

    private func treeRows(_ groups: [FileChangeGroup]) -> some View {
        let groupsByPath = Dictionary(uniqueKeysWithValues: groups.map { ($0.path, $0) })
        let rows = FileChangeTree.rows(from: groups, expanded: expandedFolders)
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if row.node.isDirectory {
                    directoryRow(row.node, depth: row.depth)
                } else if let group = groupsByPath[row.node.path] {
                    treeFileRow(group, depth: row.depth)
                    if expandedFiles.contains(group.path) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(group.changes) { change in
                                FileChangeCard(
                                    change: change,
                                    defaultExpanded: true,
                                    collapsedLines: 14,
                                    showsHeader: false
                                )
                            }
                        }
                        .padding(.leading, CGFloat(row.depth + 1) * 14 + 16)
                        .padding(.vertical, 5)
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
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: isExpanded ? "folder.fill" : "folder")
                    .font(.caption)
                    .foregroundStyle(Theme.accent.opacity(0.85))
                    .frame(width: 16)
                Text(node.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if node.changedCount > 0 {
                    Text("\(node.changedCount) changed")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.warn.opacity(0.12)))
                }
            }
            .padding(.leading, CGFloat(depth) * 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Image(systemName: group.changes.first?.statusIcon ?? "doc.text")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint(for: status))
                    .frame(width: 16)
                Text(ProjectFile(path: group.path).name)
                    .font(.system(size: 11.5, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                if group.edits > 1 {
                    Text(verbatim: "\(group.edits)×")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(verbatim: "+\(group.additions)")
                    .foregroundStyle(Theme.accent)
                Text(verbatim: "−\(group.deletions)")
                    .foregroundStyle(Theme.danger)
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .padding(.leading, CGFloat(depth) * 14 + 16)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

/// Project-wide changes grouped by the session that wrote them.
struct ProjectChangesView: View, Equatable {
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
        return VStack(alignment: .leading, spacing: 10) {
            ChangeSummaryBar(changes: changes)

            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.running)
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(2)
                            Spacer(minLength: 4)
                            Text("\(Set(group.changes.map(\.displayPath)).count)")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }

                        SessionChangesView(
                            changes: group.changes,
                            showsSummary: false,
                            expandFirst: false,
                            collapsedLines: 0
                        )
                        .equatable()
                    }
                    .card(padding: 11)
                }
            }
        }
    }
}
