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

    /// Every directory above the file, shallowest first. Used to reveal search
    /// hits inside collapsed folders.
    var ancestorDirectories: [String] {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else { return [] }
        var directories: [String] = []
        var current = ""
        for component in components.dropLast() {
            current = current.isEmpty ? String(component) : current + "/" + component
            directories.append(current)
        }
        return directories
    }
}

// MARK: - Tree

/// One directory or file in the browsable tree. Directories carry aggregate
/// counts so a collapsed folder still shows where changes are hiding.
struct ProjectFileNode: Identifiable, Hashable, Sendable {
    var path: String
    var name: String
    /// `nil` for directories.
    var file: ProjectFile?
    var children: [ProjectFileNode]
    var fileCount: Int
    var changedCount: Int

    var id: String { path }
    var isDirectory: Bool { file == nil }
}

/// Builds a directory-first tree from an already filtered file list, so the
/// All / Changed switch and the search field apply to the tree too.
enum ProjectFileTree {
    static func nodes(from files: [ProjectFile]) -> [ProjectFileNode] {
        let root = Builder(path: "", name: "")
        for file in files {
            root.insert(file)
        }
        return root.nodes()
    }

    private final class Builder {
        let path: String
        let name: String
        var directories: [String: Builder] = [:]
        var files: [ProjectFile] = []

        init(path: String, name: String) {
            self.path = path
            self.name = name
        }

        func insert(_ file: ProjectFile) {
            let components = file.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty else { return }

            var node = self
            var currentPath = path
            for component in components.dropLast() {
                currentPath = currentPath.isEmpty ? component : currentPath + "/" + component
                if let child = node.directories[component] {
                    node = child
                } else {
                    let child = Builder(path: currentPath, name: component)
                    node.directories[component] = child
                    node = child
                }
            }
            node.files.append(file)
        }

        func nodes() -> [ProjectFileNode] {
            let directories = directories.values
                .map { $0.node() }
                .sorted { ProjectFileTree.sortsBefore($0.name, $1.name) }
            let fileNodes = files
                .sorted { ProjectFileTree.sortsBefore($0.name, $1.name) }
                .map { file in
                    ProjectFileNode(
                        path: file.path,
                        name: file.name,
                        file: file,
                        children: [],
                        fileCount: 1,
                        changedCount: file.isChanged ? 1 : 0
                    )
                }
            return directories + fileNodes
        }

        private func node() -> ProjectFileNode {
            let children = nodes()
            return ProjectFileNode(
                path: path,
                name: name,
                file: nil,
                children: children,
                fileCount: children.reduce(0) { $0 + $1.fileCount },
                changedCount: children.reduce(0) { $0 + $1.changedCount }
            )
        }
    }

    /// Finder-like ordering: natural number runs, case-insensitive, with a
    /// stable path tie-break so rows never shuffle between refreshes.
    private static func sortsBefore(_ lhs: String, _ rhs: String) -> Bool {
        let result = lhs.localizedStandardCompare(rhs)
        if result != .orderedSame { return result == .orderedAscending }
        return lhs < rhs
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
