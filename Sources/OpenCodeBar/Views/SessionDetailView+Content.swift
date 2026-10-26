import SwiftUI

extension SessionDetailView {
    // MARK: - Conversation

    @ViewBuilder
    var conversation: some View {
        if isLoading && messages.isEmpty {
            ConversationSkeleton(count: 5)
                .shimmering()
        } else if let errorMessage, messages.isEmpty {
            errorState(errorMessage)
        } else if messages.isEmpty {
            EmptyState(
                icon: "bubble.left",
                title: "No messages yet",
                subtitle: "The conversation will appear as the model responds."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 7) {
                if isRunning {
                    HStack(spacing: 6) {
                        PulsingDot(size: 5)
                        Text("Generating…")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.running)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
                }

                if let failure = currentFailure {
                    failureActions(failure)
                }

                ForEach(displayMessages) { message in
                    MessageCard(message: message)
                        .equatable()
                        .transition(.recentInsertion)
                }
                .animateRecentInsertion(ids: displayMessages.map(\.id))
            }

            if previousCursor != nil {
                loadEarlierButton
            }
        }
    }

    /// Idle status messages that succeeded are bookkeeping, not conversation.
    var displayMessages: [SessionMessage] {
        messages.visibleForConversation()
    }

    /// A failure in the newest turn, used to offer retry actions.
    var currentFailure: FailedTurn? {
        guard !isRunning else { return nil }
        return messages.latestFailedTurn()
    }

    @ViewBuilder
    func failureActions(_ failure: FailedTurn) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("Last turn failed")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                if retryingFailure {
                    ProgressView().controlSize(.mini)
                }
            }
            .foregroundStyle(Theme.danger)

            Text("Retry here with the same prompt, or open Retry options to send “continue”, change settings, or fork a copy.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let retryError {
                Text(retryError)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                Button("Retry here") {
                    Task { await retryFailure(failure) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .disabled(retryingFailure)

                Button("Retry options…") {
                    retryTarget = failure
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(retryingFailure)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 9)
    }

    func retryFailure(_ failure: FailedTurn) async {
        guard !retryingFailure, let prompt = failure.promptText else { return }
        retryingFailure = true
        retryError = nil
        defer { retryingFailure = false }

        do {
            _ = try await state.retryTurn(
                from: session,
                before: failure.prompt.id,
                prompt: prompt,
                model: failure.model,
                agent: failure.agent,
                destination: .sameSession
            )
        } catch {
            retryError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Stats

    @ViewBuilder
    var stats: some View {
        let statsState = state.sessionStats[session.id]
        if let statsState, statsState.isLoading && statsState.stats == nil {
            StatsDetailSkeleton()
                .shimmering()
        } else if let statsState, let error = statsState.error, statsState.stats == nil {
            errorState(error)
        } else if let stats = statsState?.stats {
            SessionStatsView(stats: stats)
        } else {
            StatsDetailSkeleton()
                .shimmering()
        }
    }

    // MARK: - Changes

    @ViewBuilder
    var changes: some View {
        let changesState = state.sessionChanges[session.id]
        if let changesState, changesState.isLoading && changesState.changes.isEmpty {
            ChangesSkeleton()
                .shimmering()
        } else if let changesState, let error = changesState.error, changesState.changes.isEmpty {
            errorState(error)
        } else if let changes = changesState?.changes, !changes.isEmpty {
            SessionChangesView(changes: changes)
        } else {
            EmptyState(
                icon: "plus.forwardslash.minus",
                title: "No file changes",
                subtitle: "Edits and writes made by this session appear here."
            )
        }
    }

    // MARK: - Git

    @ViewBuilder
    var git: some View {
        let gitState = state.sessionGit[session.id]
        if let gitState, gitState.isLoading && gitState.git == nil {
            LoadingState(message: "Reading repository…")
        } else if let gitState, let error = gitState.error, gitState.git == nil {
            errorState(error)
        } else if let git = gitState?.git {
            SessionGitView(git: git) {
                Task { await state.loadSessionGit(session.id, force: true) }
            }
        } else {
            LoadingState(message: "Reading repository…")
        }
    }

    // MARK: - Prompts

    @ViewBuilder
    var prompts: some View {
        let prompts = messages.filter(\.isUserLike)

        if isLoading && messages.isEmpty {
            LoadingState(message: "Loading prompts…")
        } else if let errorMessage, messages.isEmpty {
            errorState(errorMessage)
        } else if prompts.isEmpty {
            EmptyState(
                icon: "text.quote",
                title: "No prompts yet",
                subtitle: "Prompts you send to this session appear here."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 7) {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, message in
                    PromptRow(index: prompts.count - index, message: message)
                        .equatable()
                        .transition(.recentInsertion)
                }
                .animateRecentInsertion(ids: prompts.map(\.id))
            }

            if previousCursor != nil {
                loadEarlierButton
            }
        }
    }

    // MARK: - Subagents

    @ViewBuilder
    var subagents: some View {
        if let list = state.subagentList(for: session.id) {
            if list.isLoading && list.sessions.isEmpty {
                SessionListSkeleton(count: 2)
                    .shimmering()
            } else if list.sessions.isEmpty {
                if let error = list.error {
                    subagentError(error)
                } else {
                    EmptyState(
                        icon: "person.2",
                        title: "No subagents",
                        subtitle: "Child sessions started by this session appear here."
                    )
                }
            } else {
                SectionHeader("Subagents") {
                    HStack(spacing: 5) {
                        if list.isLoading {
                            ProgressView().controlSize(.mini)
                        }
                        Text("\(list.sessions.count)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(list.sessions) { child in
                    Button {
                        state.open(child, from: session)
                    } label: {
                        SubagentRow(
                            session: child,
                            running: state.isRunning(child),
                            activity: state.activity(for: child.id),
                            descendants: state.activeSubagentCount(for: child.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .help("Open this subagent")
                    .transition(.recentInsertion)
                }
                .animateRecentInsertion(ids: list.sessions.map(\.id))

                if let error = list.error {
                    subagentError(error)
                }
            }
        } else {
            SessionListSkeleton(count: 2)
                .shimmering()
        }
    }

    func subagentError(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.warn)
            Text("Couldn't load subagents")
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await state.loadSubagents(session.id, force: true) }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }

    // MARK: - Shared pieces

    var loadEarlierButton: some View {
        VStack(spacing: 4) {
            Button {
                Task { await loadEarlier() }
            } label: {
                HStack(spacing: 5) {
                    if isLoadingEarlier {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    Text(isLoadingEarlier ? "Loading…" : "Load earlier")
                        .font(.system(size: 10, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .disabled(isLoadingEarlier)

            if let earlierError {
                Text(earlierError)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Reaching the end of the loaded window pages the next one in, so long
        // sessions scroll without a tap. The button stays for keyboard use.
        .onAppear {
            Task { await loadEarlier() }
        }
    }

    func errorState(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(Theme.warn)
            Text("Couldn't load this session")
                .font(.system(size: 12, weight: .medium))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await loadLatest() }
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }

    func scrollToTop(_ proxy: ScrollViewProxy, animated: Bool) {
        Task { @MainActor in
            // Let the stack lay out before jumping to the anchor.
            try? await Task.sleep(nanoseconds: 30_000_000)
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(topAnchor, anchor: .top) }
            } else {
                proxy.scrollTo(topAnchor, anchor: .top)
            }
        }
    }
}
