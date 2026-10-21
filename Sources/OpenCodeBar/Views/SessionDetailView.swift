import AppKit
import SwiftUI

/// Expanded view for a single session: at-a-glance stats, the full
/// conversation, and a prompts-only list. Opened by clicking a row on the
/// Live tab.
struct SessionDetailView: View {
    @EnvironmentObject private var state: AppState
    let session: Session

    init(session: Session, initialMode: AppState.DetailMode = .conversation) {
        self.session = session
        _mode = State(initialValue: initialMode)
    }

    @State private var mode: AppState.DetailMode
    @State private var messages: [SessionMessage] = []
    @State private var previousCursor: String?
    @State private var isLoading = true
    @State private var isLoadingEarlier = false
    @State private var earlierError: String?
    @State private var errorMessage: String?
    @State private var draft = ""
    @State private var isSending = false
    @State private var sendError: String?
    @State private var scrollRequest = 0
    @FocusState private var composerFocused: Bool
    @State private var showingNewSession = false

    private let topAnchor = "session-detail-top"

    private var isRunning: Bool { state.isRunning(session) }
    private var project: String { state.projectName(for: session) }

    /// Subagents is offered when the session has child sessions, while they are
    /// loading, or when it was selected explicitly (CLI previews).
    private var availableModes: [AppState.DetailMode] {
        var modes: [AppState.DetailMode] = [.conversation, .stats, .changes, .prompts]
        if mode == .subagents
            || state.hasSubagents(session.id)
            || state.isLoadingSubagents(session.id) {
            modes.append(.subagents)
        }
        return modes
    }

    /// Re-fetch the conversation whenever the session changes on the server.
    private var refreshKey: String {
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
                composer
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .task(id: refreshKey) {
            await loadLatest()
            if mode == .changes {
                await state.loadChanges(session.id)
            } else if mode == .stats {
                await state.loadSessionStats(session.id)
            }
        }
        .task(id: session.id) {
            await state.loadSubagents(session.id)
        }
        .task(id: mode) {
            switch mode {
            case .changes:
                await state.loadChanges(session.id)
            case .stats:
                await state.loadSessionStats(session.id)
            default:
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
    }

    // MARK: - Header

    private var navigationBar: some View {
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
                Chip(text: "Finished")
            }
        }
    }

    private var summary: some View {
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
                if let model = session.model {
                    Chip(text: model.id)
                }
                if let agent = session.agent, !agent.isEmpty {
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

    private var durationLabel: String {
        if isRunning {
            return Fmt.elapsed(since: session.time.createdDate)
        }
        return Fmt.elapsed(since: session.time.createdDate, now: session.time.updatedDate)
    }

    // MARK: - Composer

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sendError {
                Text(sendError)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 6) {
                TextField(
                    isRunning ? "Queue a message…" : "Message this session…",
                    text: $draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .lineLimit(1...4)
                .focused($composerFocused)
                .onSubmit { Task { await send() } }

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(canSend ? Theme.accent : Color.secondary.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 21, height: 21)
                .contentShape(Rectangle())
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send prompt (⌘Return)")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        composerFocused ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        isSending = true
        sendError = nil
        do {
            // A running session queues the message instead of interrupting the
            // current turn.
            try await state.promptSession(
                id: session.id,
                text: text,
                delivery: isRunning ? .queue : nil
            )
            draft = ""
            await loadLatest()
            scrollRequest += 1
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }

    // MARK: - Conversation

    @ViewBuilder
    private var conversation: some View {
        if isLoading && messages.isEmpty {
            LoadingState(message: "Loading conversation…")
        } else if let errorMessage, messages.isEmpty {
            errorState(errorMessage)
        } else if messages.isEmpty {
            EmptyState(
                icon: "bubble.left",
                title: "No messages yet",
                subtitle: "The conversation will appear as the model responds."
            )
        } else {
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

            ForEach(messages) { message in
                MessageCard(message: message)
                    .transition(.recentInsertion)
            }
            .animateRecentInsertion(ids: messages.map(\.id))

            if previousCursor != nil {
                loadEarlierButton
            }
        }
    }

    // MARK: - Stats

    @ViewBuilder
    private var stats: some View {
        let statsState = state.sessionStats[session.id]
        if let statsState, statsState.isLoading && statsState.stats == nil {
            LoadingState(message: "Measuring this session…")
        } else if let statsState, let error = statsState.error, statsState.stats == nil {
            errorState(error)
        } else if let stats = statsState?.stats {
            SessionStatsView(stats: stats)
        } else {
            LoadingState(message: "Loading stats…")
        }
    }

    // MARK: - Changes

    @ViewBuilder
    private var changes: some View {
        let changesState = state.sessionChanges[session.id]
        if let changesState, changesState.isLoading && changesState.changes.isEmpty {
            LoadingState(message: "Collecting file changes…")
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

    // MARK: - Prompts

    @ViewBuilder
    private var prompts: some View {
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
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, message in
                PromptRow(index: prompts.count - index, message: message)
                    .transition(.recentInsertion)
            }
            .animateRecentInsertion(ids: prompts.map(\.id))

            if previousCursor != nil {
                loadEarlierButton
            }
        }
    }

    // MARK: - Subagents

    @ViewBuilder
    private var subagents: some View {
        if let list = state.subagentList(for: session.id) {
            if list.isLoading && list.sessions.isEmpty {
                LoadingState(message: "Loading subagents…")
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
            LoadingState(message: "Loading subagents…")
        }
    }

    private func subagentError(_ message: String) -> some View {
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

    private var loadEarlierButton: some View {
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
    }

    private func errorState(_ message: String) -> some View {
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

    private func scrollToTop(_ proxy: ScrollViewProxy, animated: Bool) {
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

    // MARK: - Loading

    private func loadLatest() async {
        if messages.isEmpty { isLoading = true }
        defer { isLoading = false }

        do {
            let response = try await state.messages(for: session.id, limit: 100)
            guard !Task.isCancelled else { return }

            // Keep any older pages the user already loaded; refresh the newest
            // page in place so live tool output updates without losing scroll.
            let fresh = response.data
            let freshIDs = Set(fresh.map(\.id))
            let cutoff = fresh.map(\.time.created).min()
            let retained = messages.filter { message in
                guard !freshIDs.contains(message.id), let cutoff else { return false }
                return message.time.created < cutoff
            }

            messages = MessageOrdering.mostRecentFirst(fresh + retained)
            if retained.isEmpty {
                previousCursor = response.cursor?.previous
            }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if messages.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func loadEarlier() async {
        guard let cursor = previousCursor, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        earlierError = nil
        defer { isLoadingEarlier = false }

        do {
            let response = try await state.messages(for: session.id, limit: 100, cursor: cursor)
            guard !Task.isCancelled else { return }

            let existing = Set(messages.map(\.id))
            let older = response.data.filter { !existing.contains($0.id) }
            messages = MessageOrdering.mostRecentFirst(messages + older)
            previousCursor = response.cursor?.previous
        } catch {
            guard !Task.isCancelled else { return }
            earlierError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Messages

private struct MessageCard: View {
    let message: SessionMessage

    var body: some View {
        if message.isUserLike {
            userCard
        } else {
            assistantCard
        }
    }

    private var userCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: message.isSynthetic ? "wand.and.stars" : "person.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(message.roleLabel)
                    .font(.system(size: 9, weight: .bold))
                Spacer()
                Text(Fmt.relative(from: message.time.createdDate))
                    .font(.system(size: 9))
            }
            .foregroundStyle(message.isSynthetic ? Theme.warn : Theme.accent)

            if let text = message.promptText {
                Text(text)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
        )
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.running)
                Text("Assistant")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.running)
                Spacer()
                Text(Fmt.relative(from: message.time.createdDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            let parts = message.content ?? []
            if parts.isEmpty {
                Text("Working…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    PartView(part: part)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

private struct PartView: View {
    let part: MessagePart

    var body: some View {
        switch part.type {
        case "text":
            if let text = part.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "reasoning":
            if let text = part.text, !text.isEmpty {
                ReasoningPartView(text: text)
            }
        case "tool":
            ToolPartView(part: part)
        default:
            if let text = part.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ReasoningPartView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 8, weight: .bold))
                    Text("Reasoning")
                        .font(.system(size: 9, weight: .semibold))
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Theme.reasoning)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .lineLimit(expanded ? nil : 2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.reasoning.opacity(0.08))
        )
    }
}

private struct ToolPartView: View {
    let part: MessagePart

    @State private var expanded = false

    private var status: String { part.state?.status ?? "unknown" }

    private var statusColor: Color {
        switch status {
        case "running": return Theme.running
        case "completed": return Theme.accent
        case "error", "failed": return Theme.danger
        default: return .secondary
        }
    }

    private var statusIcon: String {
        switch status {
        case "running": return "ellipsis"
        case "completed": return "checkmark"
        case "error", "failed": return "xmark"
        default: return "minus"
        }
    }

    private var fileChanges: [FileChange] { part.fileChanges }

    private var hasDetails: Bool {
        part.state?.input != nil || part.state?.outputText != nil || !fileChanges.isEmpty
    }

    private var outputText: String? {
        guard expanded, let output = part.state?.outputText else { return nil }
        if output.count > 4_000 {
            return String(output.prefix(4_000)) + "\n… truncated"
        }
        return output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                guard hasDetails else { return }
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(statusColor)
                    Text(part.name ?? "tool")
                        .font(.system(size: 9, weight: .semibold))
                    if let summary = part.state?.inputSummary {
                        Text(summary)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if status == "running" {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                    if hasDetails {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if !fileChanges.isEmpty {
                    ForEach(fileChanges) { change in
                        FileChangeCard(change: change)
                    }
                } else if let input = part.state?.input {
                    Text(input.prettyString())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                }

                if let outputText {
                    Text(outputText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }
}

private struct PromptRow: View {
    let index: Int
    let message: SessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("#\(index)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                if message.isSynthetic {
                    Chip(text: "system", tint: Theme.warn)
                }
                Spacer()
                Text(Fmt.relative(from: message.time.createdDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Button {
                    copyToPasteboard(message.promptText ?? "")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy prompt")
            }

            if let text = message.promptText {
                Text(text)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
