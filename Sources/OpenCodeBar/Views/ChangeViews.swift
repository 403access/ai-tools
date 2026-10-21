import SwiftUI

// File changes written by a session. The patches come from OpenCode's
// edit/write tool metadata, so the text is the same diff the TUI shows.

struct ChangeSummaryBar: View {
    let changes: [FileChange]

    private var additions: Int { changes.reduce(0) { $0 + $1.additions } }
    private var deletions: Int { changes.reduce(0) { $0 + $1.deletions } }
    private var files: Int { Set(changes.map(\.displayPath)).count }

    var body: some View {
        HStack(spacing: 10) {
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

    @State private var expanded: Bool

    init(
        change: FileChange,
        defaultExpanded: Bool = false,
        collapsedLines: Int = 16
    ) {
        self.change = change
        self.defaultExpanded = defaultExpanded
        self.collapsedLines = collapsedLines
        _expanded = State(initialValue: defaultExpanded)
    }

    private var lines: [String] { change.patchLines }
    private var visibleLines: [String] {
        if expanded { return lines }
        guard collapsedLines > 0 else { return [] }
        return Array(lines.prefix(collapsedLines))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private var groups: [FileChangeGroup] { FileChangeGroup.grouped(changes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if showsSummary {
                ChangeSummaryBar(changes: changes)
            }

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
                            defaultExpanded: expandFirst && groups.count <= 3 && index == 0,
                            collapsedLines: collapsedLines
                        )
                    }
                }
            }
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
            let items = buckets[id] ?? []
            return SessionGroup(
                id: id,
                title: items.first?.sessionTitle ?? "Session",
                changes: items
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
