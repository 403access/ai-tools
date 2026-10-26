import AppKit
import SwiftUI

/// Expanded view for a single session: at-a-glance stats, the full
/// conversation, and a prompts-only list. Opened by clicking a row on the
/// Live tab.
struct SessionDetailView: View {
    @EnvironmentObject var state: AppState
    let session: Session

    init(session: Session, initialMode: AppState.DetailMode = .conversation) {
        self.session = session
        _mode = State(initialValue: initialMode)
    }

    @State var mode: AppState.DetailMode
    @State var messages: [SessionMessage] = []
    @State var previousCursor: String?
    @State var isLoading = true
    @State var isLoadingEarlier = false
    @State var isFetchingLatest = false
    @State var earlierError: String?
    @State var errorMessage: String?
    @State var draft = ""
    @State var isSending = false
    @State var sendError: String?
    @State var pendingError: String?
    @State var cancellingPending: Set<String> = []
    @State var scrollRequest = 0
    @StateObject var dictation = SpeechDictation()
    @FocusState var composerFocused: Bool
    @State var showingNewSession = false
    @State var retryTarget: FailedTurn?
    @State var retryingFailure = false
    @State var retryError: String?
    @State var settingsExpanded = true
    @State var defaultModelInfo: ModelInfo?
    @State var forkParent: Session?

    let topAnchor = "session-detail-top"

    var isRunning: Bool { state.isRunning(session) }
    var project: String { state.projectName(for: session) }

    /// Subagents is offered when the session has child sessions, while they are
    /// loading, or when it was selected explicitly (CLI previews).
    var availableModes: [AppState.DetailMode] {
        var modes: [AppState.DetailMode] = [.conversation, .stats, .changes, .git, .prompts]
        if mode == .subagents
            || state.hasSubagents(session.id)
            || state.isLoadingSubagents(session.id) {
            modes.append(.subagents)
        }
        return modes
    }

    /// Re-fetch the conversation whenever the session changes on the server.
    var refreshKey: String {
        "\(session.id)-\(Int(session.time.updated))-\(isRunning)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            navigationBar
            summary

            Picker("", selection: $mode) {
                ForEach(availableModes) { mode in
                    Label(mode.rawValue, systemImage: mode.icon)
                        .labelStyle(.titleAndIcon)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        Color.clear.frame(height: 1).id(topAnchor)
                        switch mode {
                        case .conversation:
                            conversation
                        case .stats:
                            stats
                        case .changes:
                            changes
                        case .git:
                            git
                        case .prompts:
                            prompts
                        case .subagents:
                            subagents
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: mode) { _, newMode in
                    guard newMode == .conversation || newMode == .prompts else { return }
                    scrollToTop(proxy, animated: false)
                }
                .onChange(of: scrollRequest) { _, _ in
                    scrollToTop(proxy, animated: true)
                }
            }

            if mode == .conversation {
                pendingQueue
                composer
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .onDisappear { dictation.cancel() }
        .task(id: refreshKey) {
            if mode == .conversation || mode == .prompts {
                await loadLatest()
            }
            if mode == .conversation {
                await state.loadPending(session.id)
            }
            if mode == .changes {
                await state.loadChanges(session.id)
            } else if mode == .stats {
                await state.loadSessionStats(session.id)
            } else if mode == .git {
                await state.loadSessionGit(session.id)
            }
        }
        .task(id: session.id) {
            await state.loadSubagents(session.id)
            await state.loadForks(session.id)
        }
        .task(id: session.id) {
            await loadDefaultModelIfNeeded()
        }
        .task(id: session.fork?.sessionID) {
            guard let sourceID = session.fork?.sessionID else {
                forkParent = nil
                return
            }
            forkParent = await state.fetchSession(id: sourceID)
        }
        .task(id: mode) {
            switch mode {
            case .conversation, .prompts:
                if messages.isEmpty { await loadLatest() }
                if mode == .conversation { await state.loadPending(session.id) }
            case .changes:
                await state.loadChanges(session.id)
            case .stats:
                await state.loadSessionStats(session.id)
            case .git:
                await state.loadSessionGit(session.id)
            case .subagents:
                break
            }
        }
        .onChange(of: availableModes, initial: true) { _, modes in
            if !modes.contains(mode) { mode = .conversation }
        }
        .onExitCommand {
            state.closeDetail()
        }
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet(directory: session.directory)
                .environmentObject(state)
        }
        .sheet(item: $retryTarget) { failure in
            RetryTurnSheet(session: session, failure: failure) { forked in
                state.open(forked)
            }
            .environmentObject(state)
        }
    }

    // MARK: - Header

    var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                state.closeDetail()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text(state.sessionBackTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to \(state.sessionBackTitle)")

            Spacer(minLength: 8)

            Button {
                showingNewSession = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Theme.accent.opacity(0.14)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .help("Start a new session")
            .accessibilityLabel("New session")

            if isRunning {
                HStack(spacing: 5) {
                    PulsingDot(size: 6)
                    Text("Running")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.running)
                }
            } else {
                Chip(
                    text: session.outcomeLabel,
                    systemImage: session.hasFailureOutcome ? "exclamationmark.triangle.fill" : nil,
                    tint: session.hasFailureOutcome ? Theme.danger : .secondary
                )
            }
        }
    }

    var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 5) {
                Text(project)
                    .font(.system(size: 10, weight: .semibold))
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

            HStack(spacing: 10) {
                Label(durationLabel, systemImage: isRunning ? "timer" : "clock")
                Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .foregroundStyle(Theme.accent)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)

            settingsRow
            forkRelationship

            if isRunning, let activity = state.activity(for: session.id) {
                Divider().opacity(0.4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        ActivityLine(activity: activity, now: context.date)
                        TodoProgressRow(activity: activity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    /// Bidirectional fork information: the conversation this session was copied
    /// from and any conversations forked from it.
    @ViewBuilder
    var forkRelationship: some View {
        let loadedForks = state.forkList(for: session.id)?.sessions ?? []
        let forks = loadedForks.isEmpty
            ? state.sessions.filter { $0.fork?.sessionID == session.id }
            : loadedForks
        let parent = forkParent ?? session.fork.flatMap { state.knownSession(id: $0.sessionID) }
        if session.isFork || !forks.isEmpty {
            HStack(spacing: 8) {
                if session.isFork {
                    Button {
                        if let parent {
                            state.open(parent)
                        }
                    } label: {
                        Label(
                            parent.map { "Fork of \($0.displayTitle)" } ?? "Fork of another session",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(parent == nil)
                    .help(parent == nil ? "The source conversation is not available offline." : "Open the source conversation")
                }

                if !forks.isEmpty {
                    Menu {
                        ForEach(forks) { fork in
                            Button(fork.displayTitle) {
                                state.open(fork)
                            }
                        }
                    } label: {
                        Label(
                            forks.count == 1 ? "1 fork" : "\(forks.count) forks",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.system(size: 9, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Conversations forked from this one")
                }
            }
            .padding(.top, 1)
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
        defaultModelInfo = try? await state.defaultModel(directory: session.directory)
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
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { settingsExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 8, weight: .semibold))
                    Text("Session settings")
                        .font(.system(size: 9, weight: .semibold))
                    Spacer()
                    Image(systemName: settingsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if settingsExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    settingLine("Agent", effectiveAgent ?? "OpenCode default")
                    settingLine("Model", effectiveModel?.id ?? "OpenCode default")
                    settingLine("Provider", effectiveModel?.providerID ?? "—")
                    settingLine("Variant", effectiveModel?.variant ?? "default")
                    settingLine("Directory", session.directory ?? "—")
                    if let latestOutcome {
                        settingLine("Outcome", latestOutcome)
                    }
                    if let fork = session.fork {
                        let parent = forkParent ?? state.knownSession(id: fork.sessionID)
                        settingLine("Forked from", parent?.displayTitle ?? fork.sessionID)
                    }
                    let forkCount = state.forkList(for: session.id)?.sessions.count
                        ?? state.sessions.filter { $0.fork?.sessionID == session.id }.count
                    if forkCount > 0 {
                        settingLine("Forks", "\(forkCount)")
                    }
                    if let error = currentFailure?.message.error {
                        settingLine("Failure", error.type ?? "failed")
                    }
                }
                .padding(.leading, 11)
            }
        }
    }

    func settingLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label.uppercased())
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
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
