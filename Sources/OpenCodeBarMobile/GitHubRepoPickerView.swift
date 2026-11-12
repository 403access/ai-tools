import SwiftUI

/// Mobile repository browser for the New Session clone flow. Repositories that
/// already exist on the hub stay visible but cannot be selected.
struct MobileGitHubRepoPickerView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let onSelect: (GitHubRepository) -> Void

    @State private var repositories: [GitHubRepository] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var available: [GitHubRepository] {
        filtered(repositories.filter { !$0.isCloned })
    }

    private var cloned: [GitHubRepository] {
        filtered(repositories.filter(\.isCloned))
    }

    private func filtered(_ entries: [GitHubRepository]) -> [GitHubRepository] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.searchText.localizedCaseInsensitiveContains(needle) }
    }

    private var visible: [GitHubRepository] {
        available + cloned
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 9) {
                if isLoading && repositories.isEmpty {
                    loadingState
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if repositories.isEmpty {
                    emptyState
                } else if visible.isEmpty {
                    noMatchesState
                } else {
                    if !available.isEmpty {
                        groupHeader("Available", count: available.count)
                        ForEach(available) { repository in
                            repoRow(repository)
                        }
                    }
                    if !cloned.isEmpty {
                        groupHeader("Already cloned", count: cloned.count)
                        ForEach(cloned) { repository in
                            repoRow(repository)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 24)
        }
        .mobileScreenBackground()
        .navigationTitle("Choose repository")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search repositories"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("Reload repositories")
            }
        }
        .task { await load() }
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .padding(.bottom, 1)
    }

    private func repoRow(_ repository: GitHubRepository) -> some View {
        Button {
            guard !repository.isCloned else { return }
            onSelect(repository)
            dismiss()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon(for: repository))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(repository.isCloned ? Color.secondary : Theme.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(repository.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if repository.isPrivate {
                            Chip(text: "Private", systemImage: "lock.fill")
                        }
                        if repository.isArchived {
                            Chip(text: "Archived")
                        }
                        if repository.isCloned {
                            Chip(text: "Cloned", systemImage: "checkmark", tint: Theme.accent)
                        }

                        Spacer(minLength: 4)

                        if let updated = repository.updatedDate {
                            Text(Fmt.relative(from: updated))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(repository.owner)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let summary = repository.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if let directory = repository.clonedDirectory {
                        Text((directory as NSString).abbreviatingWithTildeInPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                if repository.isCloned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MobileTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(MobileTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(repository.isCloned ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(repository.isCloned)
        .accessibilityLabel(repository.fullName)
        .accessibilityValue(repository.isCloned ? "Already cloned" : "")
        .accessibilityHint(
            repository.isCloned
                ? "Already cloned at \(repository.clonedDirectory ?? "")"
                : "Uses this repository for the new session"
        )
    }

    private func icon(for repository: GitHubRepository) -> String {
        if repository.isCloned { return "checkmark.circle.fill" }
        if repository.isPrivate { return "lock.fill" }
        return "arrow.triangle.branch"
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Loading your GitHub repositories…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title3)
                .foregroundStyle(Theme.warn)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await load() }
            }
            .font(.footnote.weight(.semibold))
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No repositories found")
                .font(.subheadline.weight(.medium))
            Text("Sign in with `gh auth login` or set GITHUB_TOKEN on the hub to list your repositories.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
        .padding(.horizontal, 12)
    }

    private var noMatchesState: some View {
        VStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("No repositories match")
                .font(.subheadline.weight(.medium))
            Button("Clear search") { query = "" }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await store.githubRepositories()
            repositories = loaded.filter { !$0.isArchived || $0.isCloned }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
