import SwiftUI

/// The project Git tab: branches, tags, and every reachable commit drawn as a
/// lane graph. The graph is derived from the parent hashes the hub returns, so
/// merge commits and side branches stay visible even when they interleave.
struct GitRepositoryView: View {
    let repository: GitRepository
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GitSummaryCard(summary: repository.summary, total: repository.total)

            if repository.branches.count > 1 {
                SectionHeader("Branches") {
                    Text("\(repository.branches.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GitBranchList(branches: repository.branches)
            }

            if !repository.tags.isEmpty {
                SectionHeader("Tags") {
                    Text("\(repository.tags.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                GitTagList(tags: repository.tags)
            }

            SectionHeader("Commits") {
                HStack(spacing: 5) {
                    Text(
                        repository.truncated
                            ? "\(repository.commits.count) of \(Fmt.grouped(repository.total))"
                            : "\(Fmt.grouped(repository.total))"
                    )
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                    if let onRefresh {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Reload repository")
                    }
                }
            }

            if repository.commits.isEmpty {
                EmptyState(
                    icon: "arrow.triangle.branch",
                    title: "No commits yet",
                    subtitle: "The repository has no reachable commits."
                )
            } else {
                GitCommitList(commits: repository.commits, showsGraph: true)
            }

            if repository.truncated {
                Text("Showing the newest \(Fmt.grouped(repository.commits.count)) of \(Fmt.grouped(repository.total)) commits.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warn)
            }
        }
    }
}

/// The session Git tab: the repository the session ran in and the commits made
/// while it was active. The project page owns the full graph.
struct SessionGitView: View {
    let git: SessionGit
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let repository = git.repository {
                GitSummaryCard(summary: repository)
            } else {
                EmptyState(
                    icon: "arrow.triangle.branch",
                    title: "Not a git repository",
                    subtitle: git.directory.map { "\($0) is not inside a work tree." }
                        ?? "This session has no working directory."
                )
            }

            if git.repository != nil {
                SectionHeader("Commits during this session") {
                    HStack(spacing: 5) {
                        Text(
                            git.total > git.commits.count
                                ? "\(git.commits.count) of \(Fmt.grouped(git.total))"
                                : "\(Fmt.grouped(git.total))"
                        )
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                        if let onRefresh {
                            Button(action: onRefresh) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 16, height: 16)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Reload commits")
                        }
                    }
                }

                if git.commits.isEmpty {
                    EmptyState(
                        icon: "clock.arrow.circlepath",
                        title: "No commits during this session",
                        subtitle: "Changes made by the session are listed on the Changes tab."
                    )
                } else {
                    GitCommitList(commits: git.commits, showsGraph: false)
                }
            }
        }
    }
}

// MARK: - Summary

private struct GitSummaryCard: View {
    let summary: GitRepositorySummary
    var total: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(summary.branchLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)

                if let total {
                    Text("\(Fmt.grouped(total)) commits")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                GitStatusChips(summary: summary)
            }

            if let head = summary.head {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(head.shortHash)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                        Text(head.subject)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(2)
                    }
                    HStack(spacing: 6) {
                        Text(head.author.name)
                            .lineLimit(1)
                        Text(Fmt.relative(from: head.author.date))
                        if head.isMerge {
                            Label("merge", systemImage: "arrow.merge")
                        }
                    }
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            } else {
                Text("This repository has no commits yet.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            Text((summary.root as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .card(padding: 9)
    }
}

private struct GitStatusChips: View {
    let summary: GitRepositorySummary

    var body: some View {
        HStack(spacing: 4) {
            if summary.dirty > 0 {
                chip("\(summary.dirty) changed", tint: Theme.warn)
            } else {
                chip("clean", tint: Theme.accent)
            }
            if summary.ahead > 0 {
                chip("↑\(summary.ahead)", tint: Theme.running)
            }
            if summary.behind > 0 {
                chip("↓\(summary.behind)", tint: Theme.reasoning)
            }
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - Branches and tags

private struct GitBranchList: View {
    let branches: [GitBranch]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                HStack(spacing: 6) {
                    Image(systemName: branch.current ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(branch.current ? Theme.accent : Color.secondary)
                    Text(branch.name)
                        .font(.system(size: 10, weight: branch.current ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let upstream = branch.upstream {
                        Text(upstream)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if branch.ahead > 0 {
                        Text("↑\(branch.ahead)")
                            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.running)
                    }
                    if branch.behind > 0 {
                        Text("↓\(branch.behind)")
                            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.reasoning)
                    }
                }
                .padding(.vertical, 4)
                if index != branches.count - 1 {
                    Divider().opacity(0.25)
                }
            }
        }
        .card(padding: 8)
    }
}

private struct GitTagList: View {
    let tags: [String]

    var body: some View {
        GitTagFlow(items: tags, tint: Theme.reasoning)
    }
}

/// A compact wrapping row of tag chips. SwiftUI has no built-in flow layout on
/// macOS 14, so this chunks the tags into rows that fit using a fixed estimate.
private struct GitTagFlow: View {
    let items: [String]
    var tint: Color

    var body: some View {
        let rows = chunk(items, perRow: 4)
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { item in
                        Text(item)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(tint.opacity(0.1)))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func chunk(_ values: [String], perRow: Int) -> [[String]] {
        stride(from: 0, to: values.count, by: perRow).map {
            Array(values[$0..<min($0 + perRow, values.count)])
        }
    }
}

// MARK: - Commits

struct GitCommitList: View {
    let commits: [GitCommit]
    var showsGraph = true

    private var rows: [GitGraphRow] {
        showsGraph ? GitGraph.rows(for: commits) : []
    }

    var body: some View {
        let graphRows = rows
        return LazyVStack(spacing: 0) {
            ForEach(Array(commits.enumerated()), id: \.element.id) { index, commit in
                let row = showsGraph && index < graphRows.count ? graphRows[index] : nil
                GitCommitRow(commit: commit, rail: row?.rail)
                if index != commits.count - 1 {
                    Divider().opacity(0.25)
                }
            }
        }
        .card(padding: 8)
    }
}

private struct GitCommitRow: View {
    let commit: GitCommit
    let rail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if let rail {
                Text(rail)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(minWidth: 24, maxWidth: 92, alignment: .leading)
                    .help("Commit lanes")
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(commit.shortHash)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                    Text(commit.subject)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if commit.isMerge {
                        Image(systemName: "arrow.merge")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.reasoning)
                            .help("Merge commit")
                    }
                }

                HStack(spacing: 6) {
                    Text(commit.author.name)
                        .lineLimit(1)
                    Text(Fmt.relative(from: commit.author.date))
                    ForEach(commit.displayRefs.prefix(3), id: \.self) { ref in
                        Text(ref)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(ref.hasPrefix("tag:") ? Theme.reasoning : Theme.accent)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .help("\(commit.author.name) · \(absDate)")
    }

    private var absDate: String {
        commit.author.date.formatted(date: .abbreviated, time: .shortened)
    }
}
