import Foundation

/// A layered, technical map of a project folder.
///
/// The diagram reads left to right: the project root, its top-level areas,
/// the modules inside those areas, and one more level of nested folders.
/// Edges mean containment, so a wide column is a folder with many children
/// and a deep map is a project with nested targets. Columns are capped so a
/// large checkout stays readable; nodes remember how many children were left
/// out.
struct ProjectStructure: Hashable, Sendable {
    struct Language: Identifiable, Hashable, Sendable {
        let name: String
        let files: Int

        var id: String { name }
    }

    struct Node: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let path: String
        let depth: Int
        let parentID: String?
        let fileCount: Int
        let changedCount: Int
        let languages: [Language]
        let isFile: Bool
        var hiddenChildren: Int

        var primaryLanguage: Language? { languages.first }
    }

    struct Edge: Identifiable, Hashable, Sendable {
        let parentID: String
        let childID: String

        var id: String { parentID + "\u{1F}" + childID }
    }

    var rootID: String
    var nodes: [Node]
    var edges: [Edge]
    /// Node ids per column, starting with the root column.
    var columns: [[String]]
    var totalFiles: Int
    var totalFolders: Int
    var changedFiles: Int
    var languages: [Language]
    var truncated: Bool

    func node(_ id: String) -> Node? {
        nodes.first { $0.id == id }
    }
}

/// Builds the structure map from the file list the hub already returns for the
/// Files tab. Paths are the only input, so the diagram works for any language
/// and any folder, including projects that are not git repositories.
enum ProjectStructureBuilder {
    /// At most this many nodes in one column. Together with the view's node
    /// size this keeps the canvas around 320pt tall.
    static let maxColumnNodes = 6
    static let maxRootDirectories = 4
    static let maxRootFiles = 2
    static let maxDepth = 3
    static let rootID = "/"

    private struct DirectoryStats {
        var fileCount = 0
        var changedCount = 0
        var languages: [String: Int] = [:]
        var childDirectories: Set<String> = []
    }

    static func build(name: String, project: ProjectFiles) -> ProjectStructure? {
        let files = project.files
        guard !files.isEmpty else { return nil }

        var stats: [String: DirectoryStats] = ["": DirectoryStats()]
        var rootFiles: [ProjectFile] = []

        for file in files {
            let components = file.path
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard !components.isEmpty else { continue }

            let language = ProjectFileLanguage.name(for: file.path)
            let directories = directoryPaths(for: components)
            for directory in directories {
                var entry = stats[directory] ?? DirectoryStats()
                entry.fileCount += 1
                if file.isChanged { entry.changedCount += 1 }
                entry.languages[language, default: 0] += 1
                stats[directory] = entry
            }
            for index in 1 ..< directories.count {
                stats[directories[index - 1]]?.childDirectories.insert(directories[index])
            }
            if directories.count == 1 {
                rootFiles.append(file)
            }
        }

        let rootStats = stats[""] ?? DirectoryStats()
        var nodesByID: [String: ProjectStructure.Node] = [:]
        var edges: [ProjectStructure.Edge] = []
        var columns: [[String]] = []

        let root = ProjectStructure.Node(
            id: rootID,
            name: name,
            path: "",
            depth: 0,
            parentID: nil,
            fileCount: max(project.total, rootStats.fileCount),
            changedCount: max(project.changed, rootStats.changedCount),
            languages: rankedLanguages(rootStats, limit: 4),
            isFile: false,
            hiddenChildren: 0
        )
        nodesByID[root.id] = root
        columns.append([root.id])

        // Top level: the folders that carry the project, then the manifests
        // that describe how it is built.
        let directoryChildren = rootStats.childDirectories
            .sorted { left, right in
                let leftFiles = stats[left]?.fileCount ?? 0
                let rightFiles = stats[right]?.fileCount ?? 0
                if leftFiles != rightFiles { return leftFiles > rightFiles }
                return left < right
            }
        let visibleDirectories = Array(directoryChildren.prefix(maxRootDirectories))
        let sortedRootFiles = rootFiles
            .filter(isInterestingRootFile)
            .sorted { left, right in
                let leftRank = ProjectFileLanguage.rootRank(left.path)
                let rightRank = ProjectFileLanguage.rootRank(right.path)
                if leftRank != rightRank { return leftRank < rightRank }
                return left.path.localizedStandardCompare(right.path) == .orderedAscending
            }
        let fileSlots = max(0, min(maxRootFiles, maxColumnNodes - visibleDirectories.count))
        let visibleFiles = Array(sortedRootFiles.prefix(fileSlots))

        var topLevelIDs: [String] = []
        for path in visibleDirectories {
            let node = directoryNode(path: path, depth: 1, parentID: rootID, stats: stats[path])
            nodesByID[node.id] = node
            topLevelIDs.append(node.id)
            edges.append(ProjectStructure.Edge(parentID: rootID, childID: node.id))
        }
        for file in visibleFiles {
            let language = ProjectFileLanguage.name(for: file.path)
            let node = ProjectStructure.Node(
                id: file.path,
                name: file.name,
                path: file.path,
                depth: 1,
                parentID: rootID,
                fileCount: 1,
                changedCount: file.isChanged ? 1 : 0,
                languages: [ProjectStructure.Language(name: language, files: 1)],
                isFile: true,
                hiddenChildren: 0
            )
            nodesByID[node.id] = node
            topLevelIDs.append(node.id)
            edges.append(ProjectStructure.Edge(parentID: rootID, childID: node.id))
        }

        var rootNode = root
        rootNode.hiddenChildren = max(0, directoryChildren.count - visibleDirectories.count)
        nodesByID[root.id] = rootNode
        columns.append(topLevelIDs)

        var truncated = project.truncated
            || directoryChildren.count > visibleDirectories.count
            || sortedRootFiles.count > visibleFiles.count

        // Deeper columns: give every visible parent one child per round until
        // the column is full. That keeps each area represented instead of
        // letting the largest folder fill the whole row.
        var depth = 2
        while depth <= maxDepth, let previous = columns.last, !previous.isEmpty {
            let parents = previous
                .compactMap { nodesByID[$0] }
                .filter { !$0.isFile && !(stats[$0.path]?.childDirectories.isEmpty ?? true) }
            guard !parents.isEmpty else { break }

            let childLists = parents.map { parent in
                (stats[parent.path]?.childDirectories ?? [])
                    .sorted { left, right in
                        let leftFiles = stats[left]?.fileCount ?? 0
                        let rightFiles = stats[right]?.fileCount ?? 0
                        if leftFiles != rightFiles { return leftFiles > rightFiles }
                        return left < right
                    }
            }

            var chosen: [String] = []
            var shownPerParent: [String: Int] = [:]
            var round = 0
            while chosen.count < maxColumnNodes {
                var added = false
                for (index, parent) in parents.enumerated() {
                    guard round < childLists[index].count else { continue }
                    let child = childLists[index][round]
                    chosen.append(child)
                    shownPerParent[parent.id, default: 0] += 1
                    added = true
                    if chosen.count == maxColumnNodes { break }
                }
                guard added else { break }
                round += 1
            }
            guard !chosen.isEmpty else { break }

            var columnIDs: [String] = []
            for path in chosen {
                let parentPath = parentPath(of: path)
                let parent = parents.first { $0.path == parentPath }
                let node = directoryNode(
                    path: path,
                    depth: depth,
                    parentID: parent?.id ?? rootID,
                    stats: stats[path]
                )
                nodesByID[node.id] = node
                columnIDs.append(node.id)
                edges.append(ProjectStructure.Edge(parentID: node.parentID ?? rootID, childID: node.id))
            }

            for parent in parents {
                let total = stats[parent.path]?.childDirectories.count ?? 0
                let shown = shownPerParent[parent.id] ?? 0
                if total > shown {
                    truncated = true
                    if var updated = nodesByID[parent.id] {
                        updated.hiddenChildren = total - shown
                        nodesByID[parent.id] = updated
                    }
                }
            }

            columns.append(columnIDs)
            depth += 1
        }

        let orderedNodes = columns.flatMap { ids in ids.compactMap { nodesByID[$0] } }
        return ProjectStructure(
            rootID: rootID,
            nodes: orderedNodes,
            edges: edges,
            columns: columns,
            totalFiles: max(project.total, rootStats.fileCount),
            totalFolders: max(0, stats.count - 1),
            changedFiles: max(project.changed, rootStats.changedCount),
            languages: rankedLanguages(rootStats, limit: 16),
            truncated: truncated
        )
    }

    private static func directoryNode(
        path: String,
        depth: Int,
        parentID: String,
        stats: DirectoryStats?
    ) -> ProjectStructure.Node {
        let entry = stats ?? DirectoryStats()
        return ProjectStructure.Node(
            id: path,
            name: (path as NSString).lastPathComponent,
            path: path,
            depth: depth,
            parentID: parentID,
            fileCount: entry.fileCount,
            changedCount: entry.changedCount,
            languages: rankedLanguages(entry, limit: 3),
            isFile: false,
            hiddenChildren: 0
        )
    }

    /// `""` for the root, then every parent directory of the file.
    /// `a/b/File.swift` becomes `["", "a", "a/b"]`.
    private static func directoryPaths(for components: [String]) -> [String] {
        var paths = [""]
        guard components.count > 1 else { return paths }
        var current = ""
        for component in components.dropLast() {
            current = current.isEmpty ? component : current + "/" + component
            paths.append(current)
        }
        return paths
    }

    private static func parentPath(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    private static func rankedLanguages(
        _ stats: DirectoryStats,
        limit: Int
    ) -> [ProjectStructure.Language] {
        stats.languages
            .sorted { left, right in
                if left.value != right.value { return left.value > right.value }
                return left.key < right.key
            }
            .prefix(limit)
            .map { ProjectStructure.Language(name: $0.key, files: $0.value) }
    }

    private static func isInterestingRootFile(_ file: ProjectFile) -> Bool {
        let name = file.name.lowercased()
        if name.hasSuffix("lock") || name == "package.resolved" { return false }
        if ProjectFileLanguage.rootRank(file.path) < 100 { return true }
        return ProjectFileLanguage.rootExtensions.contains(
            (file.path as NSString).pathExtension.lowercased()
        )
    }
}

/// Maps a path to a coarse language or file-type name for the diagram legend.
enum ProjectFileLanguage {
    static let rootExtensions: Set<String> = [
        "bash", "c", "conf", "cpp", "css", "go", "h", "html", "java", "js",
        "json", "kt", "md", "mjs", "nix", "plist", "py", "rb", "rs", "sh",
        "swift", "toml", "ts", "tsx", "txt", "xml", "yaml", "yml", "zsh",
    ]

    private static let manifests: [String] = [
        "package.swift",
        "package.json",
        "project.yml",
        "makefile",
        "cargo.toml",
        "go.mod",
        "pyproject.toml",
        "requirements.txt",
        "build.gradle",
        "build.gradle.kts",
        "pom.xml",
        "dockerfile",
        "docker-compose.yml",
        "compose.yml",
        "justfile",
        "flake.nix",
    ]

    /// Lower ranks sort first in the top-level file column.
    static func rootRank(_ path: String) -> Int {
        let name = (path as NSString).lastPathComponent.lowercased()
        if let index = manifests.firstIndex(of: name) { return index }
        return 100
    }

    static func name(for path: String) -> String {
        let fileName = (path as NSString).lastPathComponent.lowercased()
        switch fileName {
        case "makefile", "gnumakefile": return "Make"
        case "dockerfile": return "Docker"
        case "justfile": return "Just"
        case "procfile": return "Shell"
        default: break
        }

        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return "Swift"
        case "m", "mm": return "Objective-C"
        case "c", "h": return "C"
        case "cc", "cpp", "cxx", "hpp", "hh": return "C++"
        case "ts", "mts", "cts", "tsx": return "TypeScript"
        case "js", "mjs", "cjs", "jsx": return "JavaScript"
        case "json", "jsonc": return "JSON"
        case "md", "mdx", "markdown": return "Markdown"
        case "css", "scss", "sass", "less": return "CSS"
        case "html", "htm": return "HTML"
        case "nix": return "Nix"
        case "sh", "bash", "zsh", "fish": return "Shell"
        case "py": return "Python"
        case "rb": return "Ruby"
        case "go": return "Go"
        case "rs": return "Rust"
        case "java": return "Java"
        case "kt", "kts": return "Kotlin"
        case "php": return "PHP"
        case "yaml", "yml": return "YAML"
        case "toml": return "TOML"
        case "xml", "plist", "entitlements": return "XML"
        case "sql": return "SQL"
        case "lua": return "Lua"
        case "ex", "exs": return "Elixir"
        case "dart": return "Dart"
        case "cs": return "C#"
        case "vue": return "Vue"
        case "svelte": return "Svelte"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "icns", "pdf": return "Asset"
        case "txt": return "Text"
        case "csv": return "CSV"
        case "conf", "env": return "Config"
        default: return "Other"
        }
    }
}
