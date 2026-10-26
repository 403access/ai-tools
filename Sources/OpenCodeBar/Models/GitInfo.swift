import Foundation

// MARK: - Git

/// One person + timestamp on a commit. Times arrive as milliseconds, matching
/// the rest of the hub API.
struct GitPerson: Decodable, Hashable, Sendable {
    var name: String
    var email: String
    var time: Double

    var date: Date { Date(timeIntervalSince1970: time / 1000) }
}

/// One commit in a repository's history.
struct GitCommit: Decodable, Identifiable, Hashable, Sendable {
    var hash: String
    var shortHash: String
    var parents: [String]
    var author: GitPerson
    var committer: GitPerson
    var subject: String
    var refs: [String]

    var id: String { hash }
    var isMerge: Bool { parents.count > 1 }

    /// Ref decorations without the symbolic `HEAD ->` prefix, so rows can show
    /// a branch chip without repeating "HEAD" on every commit.
    var displayRefs: [String] {
        refs.compactMap { ref in
            guard ref.hasPrefix("HEAD -> ") else { return ref }
            return String(ref.dropFirst("HEAD -> ".count))
        }
    }
}

/// One local branch and how it tracks its upstream.
struct GitBranch: Decodable, Identifiable, Hashable, Sendable {
    var name: String
    var hash: String
    var current: Bool
    var upstream: String?
    var ahead: Int
    var behind: Int

    var id: String { name }
}

/// The at-a-glance state of a repository, shared by sessions and projects.
struct GitRepositorySummary: Decodable, Hashable, Sendable {
    var root: String
    var branch: String?
    var head: GitCommit?
    var dirty: Int
    var ahead: Int
    var behind: Int

    var branchLabel: String { branch ?? "detached HEAD" }
    var isClean: Bool { dirty == 0 }
}

/// A project repository plus its full commit graph.
struct GitRepository: Decodable, Hashable, Sendable {
    var root: String
    var branch: String?
    var head: GitCommit?
    var dirty: Int
    var ahead: Int
    var behind: Int
    var branches: [GitBranch]
    var tags: [String]
    var commits: [GitCommit]
    var total: Int
    var truncated: Bool

    var summary: GitRepositorySummary {
        GitRepositorySummary(
            root: root,
            branch: branch,
            head: head,
            dirty: dirty,
            ahead: ahead,
            behind: behind
        )
    }

    var branchLabel: String { branch ?? "detached HEAD" }
}

/// Commit information for one session. `repository` is nil when the session
/// ran outside a git work tree.
struct SessionGit: Decodable, Hashable, Sendable {
    var directory: String?
    var repository: GitRepositorySummary?
    var commits: [GitCommit]
    var total: Int
}

struct GitRepositoryResponse: Decodable {
    var data: GitRepository?
}

struct SessionGitResponse: Decodable {
    var data: SessionGit
}

// MARK: - Graph layout

/// One rendered row in a commit graph. `lanes` is the expected commit at each
/// lane before this row is consumed, which is enough to draw the vertical
/// rails and merge connectors without a separate graph library.
struct GitGraphRow: Identifiable, Hashable, Sendable {
    let commit: GitCommit
    let lane: Int
    let lanes: [String?]

    var id: String { commit.hash }

    /// Monospaced prefix such as `● │   ` used by the commit list.
    var rail: String {
        let width = max(lanes.count, lane + 1)
        var cells: [String] = []
        for index in 0..<width {
            if index == lane {
                cells.append("●")
            } else if lanes[index] != nil {
                cells.append("│")
            } else {
                cells.append(" ")
            }
        }
        return cells.joined(separator: " ")
    }
}

enum GitGraph {
    /// Assigns a lane to every commit. Git returns commits newest first, so a
    /// lane's stored hash is the commit we are still waiting to reach.
    static func rows(for commits: [GitCommit]) -> [GitGraphRow] {
        var lanes: [String?] = []
        var rows: [GitGraphRow] = []

        for commit in commits {
            var lane = lanes.firstIndex(where: { $0 == commit.hash })
            if lane == nil {
                lane = lanes.firstIndex(where: { $0 == nil }) ?? lanes.count
                if lane == lanes.count { lanes.append(nil) }
            }
            guard let lane else { continue }

            for index in lanes.indices where index != lane && lanes[index] == commit.hash {
                lanes[index] = nil
            }

            let before = lanes
            lanes[lane] = nil

            // The first parent continues in this lane; every other parent
            // opens (or joins) a side lane for the merge. A parent already
            // waiting in another lane stays there instead of being duplicated.
            for (index, parent) in commit.parents.enumerated() {
                let alreadyWaiting = lanes.enumerated().contains {
                    $0.offset != lane && $0.element == parent
                }
                guard !alreadyWaiting else { continue }

                if index == 0, lanes[lane] == nil {
                    lanes[lane] = parent
                } else if let free = lanes.firstIndex(where: { $0 == nil }) {
                    lanes[free] = parent
                } else {
                    lanes.append(parent)
                }
            }

            while let last = lanes.last, last == nil {
                lanes.removeLast()
            }

            rows.append(GitGraphRow(commit: commit, lane: lane, lanes: before))
        }

        return rows
    }
}
