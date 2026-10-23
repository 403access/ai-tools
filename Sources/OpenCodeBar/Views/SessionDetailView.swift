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

    let topAnchor = "session-detail-top"

    var isRunning: Bool { state.isRunning(session) }
    var project: String { state.projectName(for: session) }

    /// Subagents is offered when the session has child sessions, while they are
    /// loading, or when it was selected explicitly (CLI previews).
    var availableModes: [AppState.DetailMode] {
        var modes: [AppState.DetailMode] = [.conversation, .stats, .changes, .prompts]
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
            }
        }
        .task(id: session.id) {
            await state.loadSubagents(session.id)
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
                Chip(text: "Finished")
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

    var durationLabel: String {
        if isRunning {
            return Fmt.elapsed(since: session.time.createdDate)
        }
        return Fmt.elapsed(since: session.time.createdDate, now: session.time.updatedDate)
    }

}
