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
