import Foundation

/// One file changed by a tool call, with the patch OpenCode recorded. Session
/// endpoints only include the first five fields; project aggregation adds the
/// session context.
struct FileChange: Decodable, Identifiable, Hashable, Sendable {
    var file: String?
    var patch: String?
    var additions: Int
    var deletions: Int
    var status: String?
    var sessionID: String?
    var sessionTitle: String?
    var messageID: String?
    var created: Double?

    var id: String {
        [
            sessionID ?? "",
            messageID ?? "",
            file ?? "",
            created.map { String(Int($0)) } ?? "",
            String(patch?.hashValue ?? 0),
        ].joined(separator: "|")
    }

    var displayPath: String { file ?? "Unknown file" }

    var statusLabel: String {
        switch status {
        case "added": return "added"
        case "deleted": return "deleted"
        case "modified": return "modified"
        default: return "changed"
        }
    }

    var statusIcon: String {
        switch status {
        case "added": return "plus.circle.fill"
        case "deleted": return "minus.circle.fill"
        default: return "pencil.circle.fill"
        }
    }

    var patchLines: [String] {
        guard let patch, !patch.isEmpty else { return [] }
        return patch
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let text = String(line)
                return text.hasSuffix("\r") ? String(text.dropLast()) : text
            }
    }
}

struct ChangesResponse: Decodable {
    var data: [FileChange]
}

/// Groups repeated edits to the same file for the session/project summaries.
struct FileChangeGroup: Identifiable {
    var path: String
    var changes: [FileChange]

    var id: String { path }
    var additions: Int { changes.reduce(0) { $0 + $1.additions } }
    var deletions: Int { changes.reduce(0) { $0 + $1.deletions } }
    var edits: Int { changes.count }

    static func grouped(_ changes: [FileChange]) -> [FileChangeGroup] {
        var order: [String] = []
        var groups: [String: [FileChange]] = [:]
        for change in changes {
            let path = change.displayPath
            if groups[path] == nil { order.append(path) }
            groups[path, default: []].append(change)
        }
        return order.map { path in
            let changes = (groups[path] ?? []).sorted { lhs, rhs in
                let left = lhs.created ?? 0
                let right = rhs.created ?? 0
                if left != right { return left > right }
                return lhs.id < rhs.id
            }
            return FileChangeGroup(path: path, changes: changes)
        }
        .sorted { lhs, rhs in
            let left = lhs.changes.first?.created ?? 0
            let right = rhs.changes.first?.created ?? 0
            if left != right { return left > right }
            return lhs.path < rhs.path
        }
    }
}

// MARK: - Tree

/// One directory or file in the collapsible change tree. File rows map back to
/// their `FileChangeGroup`; directories aggregate the changes inside them.
struct FileChangeTreeRow: Identifiable {
    var node: ProjectFileNode
    var depth: Int

    var id: String { node.id }
}

/// Builds the change tree with the same file model as the project Files tab, so
/// folders, ordering, and counts line up between the two layouts.
enum FileChangeTree {
    static func nodes(from groups: [FileChangeGroup]) -> [ProjectFileNode] {
        ProjectFileTree.nodes(from: groups.map { group in
            // Every entry in the Changes view is a write, so a missing status
            // still counts as changed; otherwise collapsed folders would show
            // no count even though they contain edits.
            ProjectFile(path: group.path, status: group.changes.first?.status ?? "modified")
        })
    }

    /// Top-level folders to reveal when the tree first opens, so it reads as a
    /// hierarchy instead of a wall of closed folders.
    static func topLevelDirectories(from groups: [FileChangeGroup]) -> Set<String> {
        Set(groups.compactMap { ProjectFile(path: $0.path).ancestorDirectories.first })
    }

    static func rows(from groups: [FileChangeGroup], expanded: Set<String>) -> [FileChangeTreeRow] {
        flatten(nodes(from: groups), expanded: expanded)
    }

    private static func flatten(
        _ nodes: [ProjectFileNode],
        expanded: Set<String>,
        depth: Int = 0
    ) -> [FileChangeTreeRow] {
        var rows: [FileChangeTreeRow] = []
        for node in nodes {
            rows.append(FileChangeTreeRow(node: node, depth: depth))
            if node.isDirectory, expanded.contains(node.path) {
                rows.append(contentsOf: flatten(node.children, expanded: expanded, depth: depth + 1))
            }
        }
        return rows
    }
}
