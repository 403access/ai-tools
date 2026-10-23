import SwiftUI

extension SessionDetailView {
    // MARK: - Content

    @ViewBuilder
    var content: some View {
        switch mode {
        case .conversation:
            conversation
        case .stats:
            stats
        case .changes:
            changes
        case .prompts:
            prompts
        case .subagents:
            subagents
        }
    }

    @ViewBuilder
    var stats: some View {
        let state = store.sessionStats[sessionID]
        if let state, state.isLoading && state.stats == nil {
            StatsDetailSkeleton()
                .shimmering()
        } else if let state, let error = state.error, state.stats == nil {
            errorState(error, title: "Couldn't load stats")
        } else if let stats = state?.stats {
            MobileSessionStatsView(stats: stats)
        } else {
            StatsDetailSkeleton()
                .shimmering()
        }
    }

    @ViewBuilder
    var changes: some View {
        let state = store.sessionChanges[sessionID]
        if let state, state.isLoading && state.changes.isEmpty {
            ChangesSkeleton()
                .shimmering()
        } else if let state, let error = state.error, state.changes.isEmpty {
            errorState(error, title: "Couldn't load changes")
        } else if let changes = state?.changes, !changes.isEmpty {
            SessionChangesView(changes: changes)
        } else {
            EmptyState(
                icon: "plus.forwardslash.minus",
                title: "No file changes",
                subtitle: "Edits and writes made by this session appear here."
            )
        }
    }

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
            LazyVStack(alignment: .leading, spacing: 8) {
                if isRunning {
                    HStack(spacing: 6) {
                        PulsingDot(size: 5)
                        Text("Generating…")
                            .font(.caption)
                            .foregroundStyle(Theme.running)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }

                ForEach(messages) { message in
                    MessageCard(message: message)
                        .equatable()
                        .transition(.recentInsertion)
                }
                .animateRecentInsertion(ids: messages.map(\.id))

                // Inside the lazy stack so its onAppear only fires when the
                // user reaches the end, not on the first layout.
                if previousCursor != nil {
                    loadEarlierButton
                }
            }
        }
    }

    @ViewBuilder
    var prompts: some View {
        let prompts = messages.filter(\.isUserLike)
        if isLoading && messages.isEmpty {
            loading("Loading prompts…")
        } else if let errorMessage, messages.isEmpty {
            errorState(errorMessage)
        } else if prompts.isEmpty {
            EmptyState(
                icon: "text.quote",
                title: "No prompts yet",
                subtitle: "Prompts you send to this session appear here."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { index, message in
                    PromptRow(index: prompts.count - index, message: message)
                        .equatable()
                        .transition(.recentInsertion)
                }
                .animateRecentInsertion(ids: prompts.map(\.id))

                if previousCursor != nil {
                    loadEarlierButton
                }
            }
        }
    }

    @ViewBuilder
    var subagents: some View {
        if let list = store.subagentList(for: sessionID) {
            if list.isLoading && list.sessions.isEmpty {
                SessionListSkeleton(count: 2)
                    .shimmering()
            } else if list.sessions.isEmpty {
                if let error = list.error {
                    errorState(error, title: "Couldn't load subagents")
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
                            ProgressView().controlSize(.small)
                        }
                        Text("\(list.sessions.count)")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(list.sessions) { child in
                    NavigationLink(value: child) {
                        SubagentSessionRow(
                            session: child,
                            running: store.isRunning(child),
                            activity: store.activity(for: child.id),
                            descendants: store.activeSubagentCount(for: child.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.recentInsertion)
                }
                .animateRecentInsertion(ids: list.sessions.map(\.id))

                if let error = list.error {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                }
            }
        } else {
            SessionListSkeleton(count: 2)
                .shimmering()
        }
    }
}
