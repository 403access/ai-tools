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

    @State private var expanded: Bool

    init(
        change: FileChange,
        defaultExpanded: Bool = false,
        collapsedLines: Int = 18
    ) {
        self.change = change
        self.defaultExpanded = defaultExpanded
        self.collapsedLines = collapsedLines
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

    private var groups: [FileChangeGroup] { FileChangeGroup.grouped(changes) }

    var body: some View {
        let groups = self.groups
        let groupCount = groups.count
        return VStack(alignment: .leading, spacing: 9) {
            if showsSummary {
                ChangeSummaryBar(changes: changes)
            }

            // A busy session can write thousands of patches. Build file cards
            // lazily so opening the Changes tab only pays for what is on screen;
            // an eager stack made that switch block the main thread for seconds.
            LazyVStack(alignment: .leading, spacing: 9) {
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
