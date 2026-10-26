import SwiftUI

extension SessionDetailView {
    // MARK: - Header

    var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(session.displayTitle)
                .font(.headline)
                .textSelection(.enabled)

            HStack(spacing: 5) {
                Text(project)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                if let model = effectiveModel {
                    Chip(text: model.label)
                } else {
                    Chip(text: "OpenCode default", tint: Theme.reasoning)
                }
                if let agent = effectiveAgent, !agent.isEmpty {
                    Chip(text: agent, systemImage: "person.fill", tint: Theme.reasoning)
                }
            }

            HStack(spacing: 12) {
                Label(durationLabel, systemImage: isRunning ? "timer" : "clock")
                Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            settingsRow
            forkRelationship

            if isRunning, let activity = store.activity(for: sessionID) {
                Divider().opacity(0.4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 5) {
                        ActivityLine(activity: activity, now: context.date)
                        TodoProgressRow(activity: activity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 13)
    }

    /// Bidirectional fork information: the conversation this session was copied
    /// from and any conversations forked from it.
    @ViewBuilder
    var forkRelationship: some View {
        let loadedForks = store.forkList(for: sessionID)?.sessions ?? []
        let forks = loadedForks.isEmpty
            ? store.sessions.filter { $0.fork?.sessionID == sessionID }
            : loadedForks
        let parent = forkParent ?? session.fork.flatMap { store.session(id: $0.sessionID) }
        if session.isFork || !forks.isEmpty {
            HStack(spacing: 14) {
                if session.isFork {
                    Button {
                        if let parent { onOpenSession?(parent) }
                    } label: {
                        Label(
                            parent.map { "Fork of \($0.displayTitle)" } ?? "Fork of another session",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(parent == nil)
                    .accessibilityHint("Opens the source conversation")
                }

                if !forks.isEmpty {
                    Menu {
                        ForEach(forks) { fork in
                            Button(fork.displayTitle) {
                                onOpenSession?(fork)
                            }
                        }
                    } label: {
                        Label(
                            forks.count == 1 ? "1 fork" : "\(forks.count) forks",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    .accessibilityHint("Lists conversations forked from this one")
                }
            }
        }
    }

    /// Settings actually used by the newest turn. OpenCode does not always
    /// persist model/agent on the session row, so fall back to the assistant
    /// message that carried them.
    var effectiveModel: ModelRef? {
        session.model ?? latestAssistantMessage?.model ?? defaultModelInfo?.ref()
    }

    func loadDefaultModelIfNeeded() async {
        guard effectiveModel == nil else { return }
        defaultModelInfo = try? await store.defaultModel(directory: session.directory)
    }

    var effectiveAgent: String? {
        session.agent ?? latestAssistantMessage?.agent
    }

    var latestAssistantMessage: SessionMessage? {
        messages.first { $0.type == "assistant" && ($0.model != nil || $0.agent != nil) }
    }

    var latestOutcome: String? {
        session.outcome ?? messages.first(where: { $0.outcome != nil })?.outcome
    }

    @ViewBuilder
    var settingsRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { settingsExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Session settings")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if settingsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    settingLine("Agent", effectiveAgent ?? "OpenCode default")
                    settingLine("Model", effectiveModel?.id ?? "OpenCode default")
                    settingLine("Provider", effectiveModel?.providerID ?? "—")
                    settingLine("Variant", effectiveModel?.variant ?? "default")
                    settingLine("Directory", session.directory ?? "—")
                    if let latestOutcome {
                        settingLine("Outcome", latestOutcome)
                    }
                    if let fork = session.fork {
                        let parent = forkParent ?? store.session(id: fork.sessionID)
                        settingLine("Forked from", parent?.displayTitle ?? fork.sessionID)
                    }
                    let forkCount = store.forkList(for: sessionID)?.sessions.count
                        ?? store.sessions.filter { $0.fork?.sessionID == sessionID }.count
                    if forkCount > 0 {
                        settingLine("Forks", "\(forkCount)")
                    }
                    if let error = currentFailure?.message.error {
                        settingLine("Failure", error.type ?? "failed")
                    }
                }
                .padding(.leading, 15)
            }
        }
    }

    func settingLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }

    var durationLabel: String {
        if isRunning {
            return Fmt.elapsed(since: session.time.createdDate)
        }
        return Fmt.elapsed(since: session.time.createdDate, now: session.time.updatedDate)
    }
}
