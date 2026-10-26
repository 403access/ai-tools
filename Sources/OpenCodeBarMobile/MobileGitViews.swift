import SwiftUI

/// Mobile project Git section: the repository state, branches, tags, and the
/// complete commit graph. The phone shows the same data as the Mac's Git tab.
struct MobileGitRepositoryView: View {
    let repository: GitRepository
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MobileGitSummaryCard(summary: repository.summary, total: repository.total)

            if repository.branches.count > 1 {
                SectionHeader("Branches") {
                    Text("\(repository.branches.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                MobileGitBranchList(branches: repository.branches)
            }

            if !repository.tags.isEmpty {
                SectionHeader("Tags") {
                    Text("\(repository.tags.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                MobileGitTagFlow(tags: repository.tags)
            }

            SectionHeader("Commits") {
                HStack(spacing: 6) {
                    Text(
                        repository.truncated
                            ? "\(repository.commits.count) of \(Fmt.grouped(repository.total))"
                            : "\(Fmt.grouped(repository.total))"
                    )
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                    if let onRefresh {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Reload repository")
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
                MobileGitCommitList(commits: repository.commits, showsGraph: true)
            }

            if repository.truncated {
                Text("Showing the newest \(Fmt.grouped(repository.commits.count)) of \(Fmt.grouped(repository.total)) commits.")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            }
        }
    }
}

/// Mobile session Git section: the repository the session ran in and commits
/// made while it was active.
struct MobileSessionGitView: View {
    let git: SessionGit
    var onRefresh: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let repository = git.repository {
                MobileGitSummaryCard(summary: repository)
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
                    HStack(spacing: 6) {
                        Text(
                            git.total > git.commits.count
                                ? "\(git.commits.count) of \(Fmt.grouped(git.total))"
                                : "\(Fmt.grouped(git.total))"
                        )
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                        if let onRefresh {
                            Button(action: onRefresh) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 24, height: 24)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Reload commits")
                        }
                    }
                }

                if git.commits.isEmpty {
                    NoticeRow(
                        icon: "clock.arrow.circlepath",
                        message: "No commits were made while this session was active. Its file edits are on the Changes tab."
                    )
                } else {
                    MobileGitCommitList(commits: git.commits, showsGraph: false)
                }
            }
        }
    }
}

// MARK: - Summary

private struct MobileGitSummaryCard: View {
    let summary: GitRepositorySummary
    var total: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(summary.branchLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                if let total {
                    Text("\(Fmt.grouped(total)) commits")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 5) {
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
                Spacer(minLength: 0)
            }

            if let head = summary.head {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(head.shortHash)
                            .font(.caption2.weight(.semibold).monospaced())
                            .foregroundStyle(Theme.accent)
                            .textSelection(.enabled)
                        Text(head.subject)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    HStack(spacing: 7) {
                        Text(head.author.name)
                            .lineLimit(1)
                        Text(Fmt.relative(from: head.author.date))
                        if head.isMerge {
                            Label("merge", systemImage: "arrow.merge")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                )
            }

            Text((summary.root as NSString).abbreviatingWithTildeInPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .card(padding: 12)
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.12)))
    }
}

// MARK: - Branches and tags

private struct MobileGitBranchList: View {
    let branches: [GitBranch]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(branches.enumerated()), id: \.element.id) { index, branch in
                HStack(spacing: 7) {
                    Image(systemName: branch.current ? "checkmark.circle.fill" : "circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(branch.current ? Theme.accent : Color.secondary)
                    Text(branch.name)
                        .font(.caption)
                        .fontWeight(branch.current ? .semibold : .regular)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let upstream = branch.upstream {
                        Text(upstream)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if branch.ahead > 0 {
                        Text("↑\(branch.ahead)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.running)
                    }
                    if branch.behind > 0 {
                        Text("↓\(branch.behind)")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.reasoning)
                    }
                }
                .padding(.vertical, 6)
                if index != branches.count - 1 {
                    Divider().opacity(0.25)
                }
            }
        }
        .card(padding: 10)
    }
}

private struct MobileGitTagFlow: View {
    let tags: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.reasoning)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.reasoning.opacity(0.1)))
            }
        }
    }
}

// MARK: - Commits

struct MobileGitCommitList: View {
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
                MobileGitCommitRow(commit: commit, rail: row?.rail)
                if index != commits.count - 1 {
                    Divider().opacity(0.25)
                }
            }
        }
        .card(padding: 10)
    }
}

private struct MobileGitCommitRow: View {
    let commit: GitCommit
    let rail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if let rail {
                Text(rail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(minWidth: 24, maxWidth: 84, alignment: .leading)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(commit.shortHash)
                        .font(.caption2.weight(.semibold).monospaced())
                        .foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                    Text(commit.subject)
                        .font(.caption)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    if commit.isMerge {
                        Image(systemName: "arrow.merge")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.reasoning)
                            .accessibilityLabel("Merge commit")
                    }
                }

                HStack(spacing: 7) {
                    Text(commit.author.name)
                        .lineLimit(1)
                    Text(Fmt.relative(from: commit.author.date))
                    ForEach(commit.displayRefs.prefix(2), id: \.self) { ref in
                        Text(ref)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ref.hasPrefix("tag:") ? Theme.reasoning : Theme.accent)
                            .lineLimit(1)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(commit.shortHash), \(commit.subject), \(commit.author.name), \(Fmt.relative(from: commit.author.date))")
    }
}
