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

    /// One distilled technology in a folder's stack. `files` is how many files
    /// in that folder evidence the technology, so a tooltip can explain a chip
    /// without turning the map into a dependency tree.
    struct Technology: Identifiable, Hashable, Sendable {
        enum Kind: String, Hashable, Sendable {
            case runtime
            case language
            case framework
            case styling
            case tooling
            case platform
            case data

            /// Kinds sort in this order, so a stack reads from the platform it
            /// runs on toward the details layered on top.
            var rank: Int {
                switch self {
                case .runtime: return 0
                case .language: return 1
                case .framework: return 2
                case .styling: return 3
                case .tooling: return 4
                case .platform: return 5
                case .data: return 6
                }
            }

            var label: String {
                switch self {
                case .runtime: return "Runtime"
                case .language: return "Language"
                case .framework: return "Framework"
                case .styling: return "Styling"
                case .tooling: return "Tooling"
                case .platform: return "Platform"
                case .data: return "Data"
                }
            }
        }

        let name: String
        let kind: Kind
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
        /// Distilled tech stack for this folder, strongest first. Files carry
        /// only what their own path evidences.
        let stack: [Technology]
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
    /// Application-level stack, distilled from manifests and file types across
    /// the whole folder.
    var stack: [Technology]
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

    private struct TechnologyStats {
        var kind: ProjectStructure.Technology.Kind
        var files = 0
    }

    private struct DirectoryStats {
        var fileCount = 0
        var changedCount = 0
        var languages: [String: Int] = [:]
        var technologies: [String: TechnologyStats] = [:]
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
            let technologies = ProjectFileTechnology.technologies(for: file.path)
            let directories = directoryPaths(for: components)
            for directory in directories {
                var entry = stats[directory] ?? DirectoryStats()
                entry.fileCount += 1
                if file.isChanged { entry.changedCount += 1 }
                entry.languages[language, default: 0] += 1
                for technology in technologies {
                    entry.technologies[
                        technology.name,
                        default: TechnologyStats(kind: technology.kind)
                    ].files += 1
                }
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
            stack: rankedTechnologies(rootStats, limit: 16),
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
                stack: ProjectFileTechnology.technologies(for: file.path),
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
            stack: rankedTechnologies(rootStats, limit: 24),
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
            stack: rankedTechnologies(entry, limit: 6),
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

    private static func rankedTechnologies(
        _ stats: DirectoryStats,
        limit: Int
    ) -> [ProjectStructure.Technology] {
        let sorted = ProjectFileTechnology.ordered(
            stats.technologies.map { entry in
                ProjectStructure.Technology(
                    name: entry.key,
                    kind: entry.value.kind,
                    files: entry.value.files
                )
            }
        )
        return Array(distilled(sorted).prefix(limit))
    }

    /// Keeps the map readable when a project spans several ecosystems: the
    /// strongest runtime, language, framework, and styling signals survive,
    /// while long tails and incidental tooling are left to the tooltip.
    private static func distilled(
        _ technologies: [ProjectStructure.Technology]
    ) -> [ProjectStructure.Technology] {
        let limits: [ProjectStructure.Technology.Kind: Int] = [
            .runtime: 2,
            .language: 3,
            .framework: 3,
            .styling: 2,
            .tooling: 3,
            .platform: 3,
            .data: 2,
        ]
        var counts: [ProjectStructure.Technology.Kind: Int] = [:]
        return technologies.filter { technology in
            let limit = limits[technology.kind] ?? 2
            let count = counts[technology.kind, default: 0]
            guard count < limit else { return false }
            counts[technology.kind] = count + 1
            return true
        }
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

/// Distills the technologies a file evidences from its path alone.
///
/// The hub only sends paths, so manifests and lockfiles are the strongest
/// signals: a `bun.lock` says Bun, a `tsconfig.json` says TypeScript, and a
/// `docusaurus.config.js` implies React. Dependency contents are not read, so
/// the result stays a coarse app-level stack rather than a package list. File
/// types fill in the residue (Swift sources, CSS, SQL) while build noise such
/// as JSON, YAML, and Markdown is deliberately ignored.
enum ProjectFileTechnology {
    private struct Signal {
        let name: String
        let kind: ProjectStructure.Technology.Kind
    }

    static func technologies(for path: String) -> [ProjectStructure.Technology] {
        let signals = signals(for: path)
        guard !signals.isEmpty else { return [] }

        var seen: Set<String> = []
        var technologies: [ProjectStructure.Technology] = []
        for signal in signals where seen.insert(signal.name).inserted {
            technologies.append(
                ProjectStructure.Technology(name: signal.name, kind: signal.kind, files: 1)
            )
        }
        return ordered(technologies)
    }

    static func ordered(
        _ technologies: [ProjectStructure.Technology]
    ) -> [ProjectStructure.Technology] {
        technologies.sorted { left, right in
            if left.kind.rank != right.kind.rank {
                return left.kind.rank < right.kind.rank
            }
            // Languages and frameworks are about prevalence: a project with a
            // thousand Swift files should not lead with one stray TypeScript
            // config. Runtimes and tools keep a stable order instead, so Bun
            // stays ahead of Node and React ahead of Vite.
            let countsFirst = left.kind == .language || left.kind == .framework
            if countsFirst, left.files != right.files {
                return left.files > right.files
            }
            let leftRank = rank(for: left.name)
            let rightRank = rank(for: right.name)
            if leftRank != rightRank { return leftRank < rightRank }
            if left.files != right.files { return left.files > right.files }
            return left.name < right.name
        }
    }

    /// Stable order inside one kind, keeping frameworks before the utilities
    /// they depend on (React before Vite, Bun before npm) instead of letting a
    /// large generated folder pull a tool to the front.
    static func rank(for name: String) -> Int {
        switch name {
        case "Bun": return 0
        case "Deno": return 1
        case "Node": return 2
        case "TypeScript": return 10
        case "JavaScript": return 11
        case "Swift": return 12
        case "Kotlin": return 13
        case "Java": return 14
        case "C#": return 15
        case "C++": return 16
        case "C": return 17
        case "Objective-C": return 18
        case "Go": return 19
        case "Rust": return 20
        case "Python": return 21
        case "Ruby": return 22
        case "PHP": return 23
        case "Elixir": return 24
        case "Dart": return 25
        case "Lua": return 26
        case "Shell": return 27
        case "HTML": return 28
        case "React": return 30
        case "Next.js": return 31
        case "Docusaurus": return 32
        case "Vue": return 33
        case "Svelte": return 34
        case "Astro": return 35
        case "Nuxt": return 36
        case "Remix": return 37
        case "CSS": return 40
        case "Tailwind CSS": return 41
        case "Vite": return 50
        case "Webpack": return 51
        case "Rollup": return 52
        case "esbuild": return 53
        case "npm": return 54
        case "pnpm": return 55
        case "Yarn": return 56
        case "ESLint": return 57
        case "Prettier": return 58
        case "Jest": return 59
        case "Vitest": return 60
        case "Playwright": return 61
        case "Cypress": return 62
        case "PostCSS": return 63
        case "Turborepo": return 64
        case "Make": return 65
        case "Just": return 66
        case "CMake": return 67
        case "SwiftLint": return 68
        case "SwiftFormat": return 69
        case "GitHub Actions": return 70
        case "SwiftPM": return 80
        case "Xcode": return 81
        case "XcodeGen": return 82
        case "CocoaPods": return 83
        case "Cargo": return 84
        case "Gradle": return 85
        case "Maven": return 86
        case "Docker": return 87
        case "Nix": return 88
        case "Caddy": return 89
        case "Nginx": return 90
        case "Helm": return 91
        case "Android": return 92
        case "Terraform": return 93
        case "SQL": return 100
        case "Prisma": return 101
        default: return 120
        }
    }

    private static func signals(for path: String) -> [Signal] {
        var signals: [Signal] = []
        func add(_ name: String, _ kind: ProjectStructure.Technology.Kind) {
            signals.append(Signal(name: name, kind: kind))
        }

        let fileName = (path as NSString).lastPathComponent.lowercased()
        let fileExtension = (path as NSString).pathExtension.lowercased()
        let loweredPath = path.lowercased()

        switch fileName {
        case "package.json":
            add("Node", .runtime)
        case "bun.lock", "bun.lockb", "bunfig.toml":
            add("Bun", .runtime)
        case "package-lock.json", "npm-shrinkwrap.json":
            add("npm", .tooling)
        case "yarn.lock":
            add("Yarn", .tooling)
        case "pnpm-lock.yaml", "pnpm-workspace.yaml":
            add("pnpm", .tooling)
        case "deno.json", "deno.jsonc", "deno.lock":
            add("Deno", .runtime)
        case "tsconfig.json":
            add("TypeScript", .language)
        case "jsconfig.json":
            add("JavaScript", .language)
        case "package.swift":
            add("SwiftPM", .platform)
            add("Swift", .language)
        case "project.yml", "project.yaml":
            add("XcodeGen", .platform)
        case "podfile":
            add("CocoaPods", .platform)
        case "cargo.toml", "cargo.lock":
            add("Cargo", .platform)
            add("Rust", .language)
        case "go.mod", "go.sum":
            add("Go", .language)
        case "pyproject.toml", "pipfile", "poetry.lock", "uv.lock",
             "requirements.txt":
            add("Python", .language)
        case "gemfile", "gemfile.lock":
            add("Ruby", .language)
        case "composer.json", "composer.lock":
            add("PHP", .language)
        case "mix.exs", "mix.lock":
            add("Elixir", .language)
        case "pubspec.yaml", "pubspec.lock":
            add("Dart", .language)
        case "build.gradle", "build.gradle.kts", "settings.gradle",
             "settings.gradle.kts":
            add("Gradle", .platform)
        case "pom.xml":
            add("Maven", .platform)
        case "docker-compose.yml", "docker-compose.yaml", "compose.yml",
             "compose.yaml":
            add("Docker", .platform)
        case "flake.nix", "default.nix", "shell.nix":
            add("Nix", .platform)
        case "makefile", "gnumakefile":
            add("Make", .tooling)
        case "justfile":
            add("Just", .tooling)
        case "cmakelists.txt":
            add("CMake", .tooling)
        case "caddyfile":
            add("Caddy", .platform)
        case "nginx.conf":
            add("Nginx", .platform)
        case "chart.yaml":
            add("Helm", .platform)
        case "turbo.json":
            add("Turborepo", .tooling)
        case ".swiftlint.yml", ".swiftlint.yaml":
            add("SwiftLint", .tooling)
        case ".swiftformat":
            add("SwiftFormat", .tooling)
        case "androidmanifest.xml":
            add("Android", .platform)
        default:
            break
        }

        if fileName.hasPrefix("dockerfile") {
            add("Docker", .platform)
        }
        if fileName.hasPrefix("next.config.") {
            add("Next.js", .framework)
            add("React", .framework)
        }
        if fileName.hasPrefix("nuxt.config.") {
            add("Nuxt", .framework)
        }
        if fileName.hasPrefix("docusaurus.config.") {
            add("Docusaurus", .framework)
            add("React", .framework)
        }
        if fileName.hasPrefix("remix.config.") {
            add("Remix", .framework)
            add("React", .framework)
        }
        if fileName.hasPrefix("astro.config.") {
            add("Astro", .framework)
        }
        if fileName.hasPrefix("svelte.config.") {
            add("Svelte", .framework)
        }
        if fileName.hasPrefix("vite.config.") {
            add("Vite", .tooling)
        }
        if fileName.hasPrefix("vitest.config.") {
            add("Vitest", .tooling)
        }
        if fileName.hasPrefix("webpack.config.") {
            add("Webpack", .tooling)
        }
        if fileName.hasPrefix("rollup.config.") {
            add("Rollup", .tooling)
        }
        if fileName.hasPrefix("esbuild.config.") {
            add("esbuild", .tooling)
        }
        if fileName.hasPrefix("jest.config.") {
            add("Jest", .tooling)
        }
        if fileName.hasPrefix("playwright.config.") {
            add("Playwright", .tooling)
        }
        if fileName.hasPrefix("cypress.config.") {
            add("Cypress", .tooling)
        }
        if fileName.hasPrefix("tailwind.config.") {
            add("Tailwind CSS", .styling)
            add("CSS", .styling)
        }
        if fileName.hasPrefix("postcss.config.") {
            add("PostCSS", .tooling)
        }
        if fileName.hasPrefix(".eslintrc") || fileName.hasPrefix("eslint.config.") {
            add("ESLint", .tooling)
        }
        if fileName.hasPrefix(".prettierrc") || fileName.hasPrefix("prettier.config.") {
            add("Prettier", .tooling)
        }

        if loweredPath.hasPrefix(".github/workflows/")
            || loweredPath.contains("/.github/workflows/") {
            add("GitHub Actions", .tooling)
        }
        if loweredPath.contains(".xcodeproj/") || loweredPath.contains(".xcworkspace/") {
            add("Xcode", .platform)
        }

        switch fileExtension {
        case "swift":
            add("Swift", .language)
        case "m", "mm":
            add("Objective-C", .language)
        case "c", "h":
            add("C", .language)
        case "cc", "cpp", "cxx", "hpp", "hh":
            add("C++", .language)
        case "ts", "mts", "cts":
            add("TypeScript", .language)
        case "tsx":
            add("TypeScript", .language)
            add("React", .framework)
        case "jsx":
            add("JavaScript", .language)
            add("React", .framework)
        case "js", "mjs", "cjs":
            add("JavaScript", .language)
        case "vue":
            add("Vue", .framework)
        case "svelte":
            add("Svelte", .framework)
        case "css", "scss", "sass", "less":
            add("CSS", .styling)
        case "html", "htm":
            add("HTML", .language)
        case "py":
            add("Python", .language)
        case "rb":
            add("Ruby", .language)
        case "go":
            add("Go", .language)
        case "rs":
            add("Rust", .language)
        case "java":
            add("Java", .language)
        case "kt", "kts":
            add("Kotlin", .language)
        case "cs":
            add("C#", .language)
        case "php":
            add("PHP", .language)
        case "ex", "exs":
            add("Elixir", .language)
        case "dart":
            add("Dart", .language)
        case "lua":
            add("Lua", .language)
        case "sh", "bash", "zsh", "fish":
            add("Shell", .language)
        case "sql":
            add("SQL", .data)
        case "nix":
            add("Nix", .platform)
        case "prisma":
            add("Prisma", .data)
        case "tf", "tfvars":
            add("Terraform", .platform)
        case "pbxproj":
            add("Xcode", .platform)
        default:
            break
        }

        return signals
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
