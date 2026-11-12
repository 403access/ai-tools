import SwiftUI

/// Picks a repository from the hub owner's GitHub account for the New Session
/// clone flow. Repositories that already exist on the hub are listed but
/// disabled, with the folder they were cloned into.
struct GitHubRepoPickerSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let onSelect: (GitHubRepository) -> Void

    @State private var repositories: [GitHubRepository] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hoveredID: Int?
    @State private var focusedID: Int?
    @FocusState private var searchFocused: Bool

    private var available: [GitHubRepository] {
        repositories.filter { !$0.isCloned }
    }

    private var cloned: [GitHubRepository] {
        repositories.filter(\.isCloned)
    }

    private var filteredAvailable: [GitHubRepository] {
        filtered(available)
    }

    private var filteredCloned: [GitHubRepository] {
        filtered(cloned)
    }

    private func filtered(_ entries: [GitHubRepository]) -> [GitHubRepository] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter { $0.searchText.localizedCaseInsensitiveContains(needle) }
    }

    private var visible: [GitHubRepository] {
        filteredAvailable + filteredCloned
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            searchField
            Divider().opacity(0.35)
            results
            footer
        }
        .padding(15)
        .frame(width: 480, height: 540)
        .task { await load() }
        .onAppear {
            focusedID = visible.first(where: { !$0.isCloned })?.id
            searchFocused = true
        }
        .onChange(of: visible.map(\.id)) { _, ids in
            if let focusedID, ids.contains(focusedID) { return }
            focusedID = ids.first
        }
        .onKeyPress(.downArrow) {
            moveFocus(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            moveFocus(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            chooseFocused()
            return .handled
        }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose a GitHub repository")
                    .font(.system(size: 15, weight: .semibold))
                Text("Repositories from the GitHub login on your Mac. Already cloned repositories are dimmed.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                Task { await load() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reload repositories")
            .disabled(isLoading)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close without changing the repository")
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(searchFocused ? Theme.accent : Color.secondary.opacity(0.7))

            TextField("Search repositories", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .focused($searchFocused)
                .onSubmit { chooseFocused() }

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    searchFocused ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.05),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var results: some View {
        if isLoading && repositories.isEmpty {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading your GitHub repositories…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            VStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.warn)
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    Task { await load() }
                }
                .disabled(isLoading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        } else if repositories.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No repositories found")
                    .font(.system(size: 12, weight: .medium))
                Text("Sign in with `gh auth login` or set GITHUB_TOKEN on the hub to list your repositories.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
        } else if visible.isEmpty {
            VStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("No repositories match")
                    .font(.system(size: 12, weight: .medium))
                Button("Clear search") { query = "" }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if !filteredAvailable.isEmpty {
                            groupHeader("Available", count: filteredAvailable.count)
                            ForEach(filteredAvailable) { repository in
                                repoRow(repository)
                                    .id(repository.id)
                            }
                        }
                        if !filteredCloned.isEmpty {
                            groupHeader("Already cloned", count: filteredCloned.count)
                            ForEach(filteredCloned) { repository in
                                repoRow(repository)
                                    .id(repository.id)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: focusedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.16)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 5)
        .padding(.top, 7)
        .padding(.bottom, 1)
    }

    private func repoRow(_ repository: GitHubRepository) -> some View {
        let isCloned = repository.isCloned
        let isFocused = focusedID == repository.id
        let isHovered = hoveredID == repository.id

        return Button {
            choose(repository)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon(for: repository))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isCloned ? Color.secondary : Theme.accent)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(repository.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if repository.isPrivate {
                            Chip(text: "Private", systemImage: "lock.fill")
                        }
                        if repository.isArchived {
                            Chip(text: "Archived")
                        }
                        if isCloned {
                            Chip(text: "Cloned", systemImage: "checkmark", tint: Theme.accent)
                        }

                        Spacer(minLength: 5)

                        if let updated = repository.updatedDate {
                            Text(Fmt.relative(from: updated))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(repository.owner)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)

                    if let summary = repository.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if let directory = repository.clonedDirectory {
                        Text((directory as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowFill(isFocused: isFocused, isHovered: isHovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isFocused ? Theme.accent.opacity(0.16) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
            .opacity(isCloned ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isCloned)
        .help(isCloned ? "Already cloned at \(repository.clonedDirectory ?? "")" : "Clone \(repository.fullName)")
        .onHover { inside in
            if inside {
                hoveredID = repository.id
                if !isCloned { focusedID = repository.id }
            } else if hoveredID == repository.id {
                hoveredID = nil
            }
        }
        .accessibilityLabel("\(repository.fullName)")
        .accessibilityValue(isCloned ? "Already cloned" : "")
    }

    private func icon(for repository: GitHubRepository) -> String {
        if repository.isCloned { return "checkmark.circle.fill" }
        if repository.isPrivate { return "lock.fill" }
        return "arrow.triangle.branch"
    }

    private func rowFill(isFocused: Bool, isHovered: Bool) -> Color {
        if isHovered { return Color.primary.opacity(0.065) }
        if isFocused { return Color.primary.opacity(0.035) }
        return .clear
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if !repositories.isEmpty {
                Text("\(available.count) available · \(cloned.count) cloned")
                    .font(.system(size: 9.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("↑↓ move · ↩ choose · esc close")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func choose(_ repository: GitHubRepository) {
        guard !repository.isCloned else { return }
        onSelect(repository)
        dismiss()
    }

    private func chooseFocused() {
        guard let focusedID,
              let repository = visible.first(where: { $0.id == focusedID }) ?? visible.first
        else { return }
        choose(repository)
    }

    private func moveFocus(by offset: Int) {
        let ids = visible.map(\.id)
        guard !ids.isEmpty else { return }
        guard let focusedID,
              let index = ids.firstIndex(of: focusedID)
        else {
            self.focusedID = offset > 0 ? ids.first : ids.last
            return
        }
        let next = min(max(index + offset, 0), ids.count - 1)
        self.focusedID = ids[next]
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await state.githubRepositories()
            repositories = loaded.filter { !$0.isArchived || $0.isCloned }
            if focusedID == nil {
                focusedID = repositories.first(where: { !$0.isCloned })?.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
