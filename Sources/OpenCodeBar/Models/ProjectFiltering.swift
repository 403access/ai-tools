import Foundation

/// How the project browser orders its list. The browser groups the sorted
/// results so the order is readable at a glance instead of one long feed.
enum ProjectSortOrder: String, CaseIterable, Identifiable, Hashable, Sendable {
    /// Most recently active first, with running work pinned to the top.
    case recent = "Recent"
    /// One A–Z list grouped by first letter.
    case name = "Name"
    /// Projects with the most running sessions first.
    case running = "Running"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: return "Last active"
        case .name: return "Name"
        case .running: return "Running work"
        }
    }

    /// Compact label for a segmented control or filter chip.
    var shortTitle: String {
        switch self {
        case .recent: return "Recent"
        case .name: return "A–Z"
        case .running: return "Running"
        }
    }

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .name: return "textformat.abc"
        case .running: return "bolt.fill"
        }
    }

    var help: String {
        switch self {
        case .recent: return "Most recently active projects first"
        case .name: return "Projects sorted alphabetically"
        case .running: return "Projects with the most running sessions first"
        }
    }
}

/// Narrows the project browser without searching. A project can be running,
/// a Git checkout, and have sandboxes at the same time, so these are presented
/// as one-choice chips rather than independent toggles.
enum ProjectFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case running
    case git
    case sandboxed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All projects"
        case .running: return "Running now"
        case .git: return "Git repositories"
        case .sandboxed: return "With sandboxes"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: return "All"
        case .running: return "Running"
        case .git: return "Git"
        case .sandboxed: return "Sandboxes"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .running: return "bolt.fill"
        case .git: return "arrow.triangle.branch"
        case .sandboxed: return "shippingbox.fill"
        }
    }

    func matches(_ project: Project, runningCounts: [String: Int]) -> Bool {
        switch self {
        case .all:
            return true
        case .running:
            return (runningCounts[project.id] ?? 0) > 0
        case .git:
            return (project.vcs ?? "").localizedCaseInsensitiveCompare("git") == .orderedSame
        case .sandboxed:
            return !project.sandboxes.isEmpty
        }
    }
}

/// Everything the browser needs to describe the current list. Keeping this in
/// one value makes state changes easy to animate and test.
struct ProjectQuery: Equatable, Sendable {
    var search = ""
    var filter: ProjectFilter = .all
    var sort: ProjectSortOrder = .recent

    var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A titled run of projects in the browser. Titles are plain text; the views
/// decide how to style them on each platform.
struct ProjectGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let projects: [Project]
}

extension Project {
    /// Text a project search should match. The display name, canonical path,
    /// tilde-abbreviated path, VCS label, and sandbox directories are all fair
    /// game, so typing either end of a path finds the project.
    var searchableText: [String] {
        [
            displayName,
            name ?? "",
            canonical,
            (canonical as NSString).abbreviatingWithTildeInPath,
            vcs ?? "",
        ] + sandboxes
    }

    func matchesProjectSearch(_ needle: String) -> Bool {
        let normalized = needle.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        guard !normalized.isEmpty else { return true }
        return searchableText.contains { value in
            value.folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: .current
            )
            .contains(normalized)
        }
    }
}

extension Array where Element == Project {
    /// Case- and diacritic-insensitive search across each project's useful
    /// labels. A blank query leaves the list untouched.
    func matchingProjectSearch(_ search: String) -> [Project] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return self }
        return filter { $0.matchesProjectSearch(needle) }
    }

    /// Applies the active chip and free-text query. Counts are intentionally
    /// not part of this step so the browser can show every chip's total for
    /// the current search.
    func filteringProjects(
        query: ProjectQuery,
        runningCounts: [String: Int]
    ) -> [Project] {
        matchingProjectSearch(query.search).filter {
            query.filter.matches($0, runningCounts: runningCounts)
        }
    }

    func sortedProjects(
        by sort: ProjectSortOrder,
        runningCounts: [String: Int]
    ) -> [Project] {
        sorted { lhs, rhs in
            switch sort {
            case .recent:
                if lhs.lastActiveDate != rhs.lastActiveDate {
                    return lhs.lastActiveDate > rhs.lastActiveDate
                }
            case .name:
                let result = lhs.displayName.localizedStandardCompare(rhs.displayName)
                if result != .orderedSame { return result == .orderedAscending }
            case .running:
                let left = runningCounts[lhs.id] ?? 0
                let right = runningCounts[rhs.id] ?? 0
                if left != right { return left > right }
                if lhs.lastActiveDate != rhs.lastActiveDate {
                    return lhs.lastActiveDate > rhs.lastActiveDate
                }
            }

            let result = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if result != .orderedSame { return result == .orderedAscending }
            return lhs.canonical < rhs.canonical
        }
    }

    func applyingProjectQuery(
        _ query: ProjectQuery,
        runningCounts: [String: Int]
    ) -> [Project] {
        filteringProjects(query: query, runningCounts: runningCounts)
            .sortedProjects(by: query.sort, runningCounts: runningCounts)
    }
}

enum ProjectGrouping {
    /// Groups already-sorted projects into readable sections. Running work is
    /// always pinned first in the recent/running sorts, matching the rest of
    /// the app, and name sorting gets one section per initial.
    static func groups(
        for projects: [Project],
        sort: ProjectSortOrder,
        runningCounts: [String: Int],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [ProjectGroup] {
        switch sort {
        case .recent:
            return recentGroups(
                projects: projects,
                runningCounts: runningCounts,
                now: now,
                calendar: calendar
            )
        case .name:
            return nameGroups(projects: projects)
        case .running:
            return runningGroups(projects: projects, runningCounts: runningCounts)
        }
    }

    private static func recentGroups(
        projects: [Project],
        runningCounts: [String: Int],
        now: Date,
        calendar: Calendar
    ) -> [ProjectGroup] {
        let running = projects.filter { (runningCounts[$0.id] ?? 0) > 0 }
        let rest = projects.filter { (runningCounts[$0.id] ?? 0) == 0 }
        var groups: [ProjectGroup] = []

        if !running.isEmpty {
            groups.append(ProjectGroup(id: "running", title: "Running now", projects: running))
        }

        var bucketOrder: [String] = []
        var buckets: [String: [Project]] = [:]
        for project in rest {
            let title = recentBucketTitle(
                for: project.lastActiveDate,
                now: now,
                calendar: calendar
            )
            if buckets[title] == nil { bucketOrder.append(title) }
            buckets[title, default: []].append(project)
        }
        for title in bucketOrder {
            groups.append(
                ProjectGroup(
                    id: "recent:\(title)",
                    title: title,
                    projects: buckets[title] ?? []
                )
            )
        }
        return groups
    }

    private static func recentBucketTitle(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return "This week"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return "This month"
        }
        return "Earlier"
    }

    private static func nameGroups(projects: [Project]) -> [ProjectGroup] {
        var order: [String] = []
        var buckets: [String: [Project]] = [:]
        for project in projects {
            let key = nameSectionKey(for: project.displayName)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(project)
        }
        return order.map { key in
            ProjectGroup(
                id: "name:\(key)",
                title: key,
                projects: buckets[key] ?? []
            )
        }
    }

    private static func nameSectionKey(for name: String) -> String {
        guard let first = name.trimmingCharacters(in: .whitespacesAndNewlines).first,
              first.isLetter || first.isNumber
        else { return "#" }
        return String(first).uppercased()
    }

    private static func runningGroups(
        projects: [Project],
        runningCounts: [String: Int]
    ) -> [ProjectGroup] {
        let running = projects.filter { (runningCounts[$0.id] ?? 0) > 0 }
        let rest = projects.filter { (runningCounts[$0.id] ?? 0) == 0 }
        var groups: [ProjectGroup] = []
        if !running.isEmpty {
            groups.append(ProjectGroup(id: "running", title: "Running now", projects: running))
        }
        if !rest.isEmpty {
            groups.append(ProjectGroup(id: "idle", title: "Other projects", projects: rest))
        }
        return groups
    }
}
