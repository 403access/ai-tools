import Foundation

// MARK: - Kinds

/// What a command-bar result points at. The order of the cases is also the
/// priority used when several kinds match the same query: projects first,
/// sessions second, and everything else after them.
enum CommandKind: String, CaseIterable, Sendable {
    case project
    case session
    case navigation
    case app
    case terminal
    case device
    case action
}

/// A group of results. Favorites sit above the type sections; the remaining
/// order keeps projects ahead of sessions and everything else behind them.
enum CommandSectionKind: String, CaseIterable, Sendable {
    case favorites
    case projects
    case sessions
    case navigation
    case apps
    case terminals
    case devices
    case actions

    var title: String {
        switch self {
        case .favorites: return "Favorites"
        case .projects: return "Projects"
        case .sessions: return "Sessions"
        case .navigation: return "Go to"
        case .apps: return "Apps"
        case .terminals: return "Terminals"
        case .devices: return "Devices"
        case .actions: return "Actions"
        }
    }

    var icon: String {
        switch self {
        case .favorites: return "star.fill"
        case .projects: return "folder.fill"
        case .sessions: return "bubble.left.and.bubble.right.fill"
        case .navigation: return "arrow.turn.down.right"
        case .apps: return "square.grid.2x2.fill"
        case .terminals: return "terminal.fill"
        case .devices: return "iphone"
        case .actions: return "bolt.fill"
        }
    }

    var commandKind: CommandKind {
        switch self {
        case .favorites: return .action
        case .projects: return .project
        case .sessions: return .session
        case .navigation: return .navigation
        case .apps: return .app
        case .terminals: return .terminal
        case .devices: return .device
        case .actions: return .action
        }
    }

    /// Everything after `sessions` is "remaining stuff" and shares one lower
    /// priority band.
    var priority: Int {
        switch self {
        case .favorites: return 0
        case .projects: return 1
        case .sessions: return 2
        case .navigation: return 3
        case .apps: return 4
        case .terminals: return 5
        case .devices: return 6
        case .actions: return 7
        }
    }
}

/// Palette colour names resolved by the view, so the search model stays free of
/// SwiftUI and can be unit tested.
enum CommandTint: String, Hashable, Sendable {
    case accent
    case running
    case warning
    case danger
    case secondary
    case reasoning
}

/// The artwork a result should render. Projects use their real app icon, apps
/// load theirs from the hub, and everything else falls back to an SF Symbol.
enum CommandIcon: Hashable, Sendable {
    case symbol(String)
    case project(String)
    case app(path: String, hasIcon: Bool)
}

/// Navigation a result performs. Keeping actions as data lets the palette rank
/// and test results without touching `AppState`.
enum CommandAction: Hashable, Sendable {
    case openProject(String)
    case openSession(String)
    case selectTab(String)
    case openSystemApp(String)
    case openTerminal(String)
    case openHostTerminal(String)
    case openDevice(String)
    case openDeploymentDevice(String)
    case refresh
    case sync
    case toggleDesktopWindow
}

// MARK: - Item

struct CommandItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: CommandKind
    let title: String
    let subtitle: String
    let icon: CommandIcon
    let tint: CommandTint
    let badge: String?
    let badgeTint: CommandTint
    let isRunning: Bool
    let recency: Date?
    let keywords: [String]
    let action: CommandAction
}

struct CommandSection: Identifiable, Hashable, Sendable {
    let kind: CommandSectionKind
    let items: [CommandItem]

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var icon: String { kind.icon }
}

// MARK: - Ranking

/// Pure ranking used by the command bar. Search is intentionally forgiving:
/// titles, paths, ids, labels, and keyword lists all contribute, and prefix
/// matches beat matches buried in the middle of a path.
enum CommandPalette {
    struct Limits: Sendable {
        var favorites = 8
        var perSection = 10
        var emptyProjects = 6
        var emptySessions = 8

        static let standard = Limits()
    }

    static func sections(
        items: [CommandItem],
        favoriteIDs: [String],
        query: String,
        limits: Limits = .standard
    ) -> [CommandSection] {
        let needle = normalized(query)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !needle.isEmpty

        var byID: [String: CommandItem] = [:]
        byID.reserveCapacity(items.count)
        for item in items {
            byID[item.id] = item
        }

        var result: [CommandSection] = []
        var used: Set<String> = []

        // Favorites are the user's own priority and always come first.
        let favoriteItems = favoriteIDs.compactMap { byID[$0] }
        if !favoriteItems.isEmpty {
            var selected: [CommandItem]
            if isSearching {
                selected = ranked(favoriteItems, needle: needle)
                selected = Array(selected.prefix(limits.perSection))
            } else {
                selected = Array(favoriteItems.prefix(limits.favorites))
            }
            if !selected.isEmpty {
                result.append(CommandSection(kind: .favorites, items: selected))
                used.formUnion(selected.map(\.id))
            }
        }

        // Project > session > everything else. Favorites are removed from the
        // type sections so a pinned result never appears twice.
        let orderedKinds = CommandSectionKind.allCases
            .filter { $0 != .favorites }
            .sorted { $0.priority < $1.priority }

        for kind in orderedKinds {
            var group = items.filter { $0.kind == kind.commandKind && !used.contains($0.id) }
            guard !group.isEmpty else { continue }

            if isSearching {
                group = ranked(group, needle: needle)
                group = Array(group.prefix(limits.perSection))
            } else {
                switch kind {
                case .projects:
                    group = Array(group.sorted(by: recentFirst).prefix(limits.emptyProjects))
                case .sessions:
                    group = Array(group.sorted(by: recentFirst).prefix(limits.emptySessions))
                case .navigation, .actions:
                    group = Array(group.prefix(limits.perSection))
                case .favorites, .apps, .terminals, .devices:
                    continue
                }
            }

            if !group.isEmpty {
                result.append(CommandSection(kind: kind, items: group))
            }
        }

        return result
    }

    /// `nil` when the item does not match every term in the query.
    static func score(_ item: CommandItem, query: String) -> Int? {
        let needle = normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return 0 }

        let terms = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        var total = 0
        for term in terms {
            guard let value = score(term: term, item: item) else { return nil }
            total += value
        }

        // Running work is useful context and wins ties inside a section.
        if item.isRunning { total += 30 }
        return total
    }

    static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - Private

    private static func ranked(_ items: [CommandItem], needle: String) -> [CommandItem] {
        items
            .compactMap { item -> (item: CommandItem, score: Int)? in
                guard let score = score(item, query: needle) else { return nil }
                return (item, score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.item.isRunning != rhs.item.isRunning { return lhs.item.isRunning }
                let left = lhs.item.recency ?? .distantPast
                let right = rhs.item.recency ?? .distantPast
                if left != right { return left > right }
                return lhs.item.title.localizedCaseInsensitiveCompare(rhs.item.title) == .orderedAscending
            }
            .map(\.item)
    }

    private static func recentFirst(_ lhs: CommandItem, _ rhs: CommandItem) -> Bool {
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        let left = lhs.recency ?? .distantPast
        let right = rhs.recency ?? .distantPast
        if left != right { return left > right }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func score(term: String, item: CommandItem) -> Int? {
        let title = normalized(item.title)
        let subtitle = normalized(item.subtitle)
        let keywords = normalized(item.keywords.joined(separator: " "))

        if title == term { return 1_400 }
        if title.hasPrefix(term) { return 1_200 }
        if titleWords(title).contains(where: { $0.hasPrefix(term) }) { return 1_000 }
        if title.contains(term) { return 820 }
        if subtitle.hasPrefix(term) { return 700 }
        if subtitle.contains(term) { return 520 }
        if keywordWords(keywords).contains(where: { $0.hasPrefix(term) }) { return 440 }
        if keywords.contains(term) { return 300 }

        // A short subsequence still helps with abbreviations such as "prj"
        // for "project", without letting one stray letter match everything.
        if term.count >= 2, isSubsequence(term, of: title) { return 180 }
        if term.count >= 2, isSubsequence(term, of: subtitle) { return 90 }
        return nil
    }

    private static func titleWords(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func keywordWords(_ text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var index = haystack.startIndex
        for character in needle {
            guard let found = haystack[index...].firstIndex(of: character) else { return false }
            index = haystack.index(after: found)
        }
        return true
    }
}
