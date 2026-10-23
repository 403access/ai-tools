import Foundation

// MARK: - Project files

/// One file in a project directory. `status` comes from git's working tree, so
/// unchanged files only have a path.
struct ProjectFile: Decodable, Identifiable, Hashable, Sendable {
    var path: String
    var status: String?

    var id: String { path }
    var isChanged: Bool { status != nil }

    var name: String {
        (path as NSString).lastPathComponent
    }

    /// Everything before the file name, with a trailing slash. Empty at the root.
    var directory: String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? "" : parent + "/"
    }

    var statusLabel: String {
        switch status {
        case "added": return "Added"
        case "modified": return "Modified"
        case "deleted": return "Deleted"
        case "renamed": return "Renamed"
        default: return "Changed"
        }
    }

    var statusIcon: String {
        switch status {
        case "added": return "plus.circle.fill"
        case "modified": return "pencil.circle.fill"
        case "deleted": return "minus.circle.fill"
        case "renamed": return "arrow.triangle.2.circlepath.circle.fill"
        case nil: return "doc.text"
        default: return "circle.fill"
        }
    }
}

struct ProjectFiles: Decodable, Hashable, Sendable {
    var files: [ProjectFile]
    var vcs: String?
    var changed: Int
    var total: Int
    var truncated: Bool
}

struct ProjectFilesResponse: Decodable {
    var data: ProjectFiles
}
