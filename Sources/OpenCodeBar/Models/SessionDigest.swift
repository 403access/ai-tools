import Foundation

/// Project-grouped, status-only view of sessions for Lock Screen surfaces.
///
/// The Lock Screen widget and the Live Activity share this so both rank and
/// truncate the same way: running work first, then review/failed work, then
/// paused/stopped/queued sessions, grouped by project. Moment-to-moment
/// activity is intentionally absent.
struct SessionDigest: Equatable, Sendable {
    struct Item: Identifiable, Equatable, Hashable, Sendable {
        var id: String
        var title: String
        var projectID: String?
        var project: String
        var status: WidgetSnapshot.Session.Status
        var updatedAt: Date
    }

    struct Group: Identifiable, Equatable, Hashable, Sendable {
        var projectID: String?
        var project: String
        var entries: [Item]
        /// Sessions in this project that did not fit.
        var hidden: Int

        var id: String { projectID ?? project }
    }

    var groups: [Group]
    /// Items that did not fit across all groups.
    var hidden: Int

    var isEmpty: Bool { groups.isEmpty }

    /// - Parameters:
    ///   - maxRows: Combined budget for project headers and session rows.
    ///   - maxGroups: Upper bound on projects, also limited by the row budget.
    ///   - maxEntriesPerGroup: Extra sessions a project may receive once every
    ///     project has one row.
    static func make(
        running: [Item],
        recent: [Item],
        maxRows: Int,
        maxGroups: Int,
        maxEntriesPerGroup: Int
    ) -> SessionDigest {
        let eligible = (running + recent).filter { $0.status.appearsOnLockScreen }
        guard !eligible.isEmpty else {
            return SessionDigest(groups: [], hidden: 0)
        }

        // Preserve the first-seen project order, then rank inside each project.
        var order: [String] = []
        var grouped: [String: [Item]] = [:]
        for item in eligible {
            let key = item.projectID ?? item.project
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(item)
        }

        let ranked = order.compactMap { key -> (key: String, items: [Item])? in
            guard let items = grouped[key], !items.isEmpty else { return nil }
            return (
                key,
                items.sorted { lhs, rhs in
                    let left = priority(lhs.status)
                    let right = priority(rhs.status)
                    if left != right { return left < right }
                    return lhs.updatedAt > rhs.updatedAt
                }
            )
        }
        .sorted { lhs, rhs in
            let left = lhs.items.first.map { priority($0.status) } ?? .max
            let right = rhs.items.first.map { priority($0.status) } ?? .max
            if left != right { return left < right }
            let leftDate = lhs.items.first?.updatedAt ?? .distantPast
            let rightDate = rhs.items.first?.updatedAt ?? .distantPast
            return leftDate > rightDate
        }

        // Every project gets a header plus one session first; leftover rows are
        // spread round-robin so one chatty project cannot crowd out the rest.
        let groupCount = min(maxGroups, ranked.count, max(1, maxRows / 2))
        var allocations = Array(repeating: 1, count: groupCount)
        var remaining = max(0, maxRows - groupCount * 2)

        while remaining > 0 {
            var grew = false
            for index in 0..<groupCount where remaining > 0 {
                let capacity = min(maxEntriesPerGroup, ranked[index].items.count)
                if allocations[index] < capacity {
                    allocations[index] += 1
                    remaining -= 1
                    grew = true
                }
            }
            if !grew { break }
        }

        var groups: [Group] = []
        var shown = 0
        for index in 0..<groupCount {
            let rankedGroup = ranked[index]
            let visible = Array(rankedGroup.items.prefix(allocations[index]))
            guard let first = visible.first else { continue }
            shown += visible.count
            groups.append(Group(
                projectID: first.projectID,
                project: first.project,
                entries: visible,
                hidden: rankedGroup.items.count - visible.count
            ))
        }

        return SessionDigest(
            groups: groups,
            hidden: max(0, eligible.count - shown)
        )
    }

    private static func priority(_ status: WidgetSnapshot.Session.Status) -> Int {
        switch status {
        case .running: return 0
        case .review: return 1
        case .failed: return 2
        case .interrupted: return 3
        case .paused: return 4
        case .stopped: return 5
        case .queued: return 6
        default: return 7
        }
    }
}
