import SwiftUI
import UIKit

/// Mobile session detail: live header, conversation, prompts, and subagents.
struct SessionDetailView: View {
    @EnvironmentObject private var store: MobileStore
    let sessionID: String
    let fallback: Session

    @State private var mode: MobileStore.DetailMode = .conversation

    init(sessionID: String, fallback: Session) {
        self.sessionID = sessionID
        self.fallback = fallback
        #if DEBUG
        // Screenshot tooling: SIMCTL_CHILD_OPENCODEBAR_DETAIL_MODE=changes
        if let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_DETAIL_MODE"],
           let mode = MobileStore.DetailMode(rawValue: requested.capitalized) {
            _mode = State(initialValue: mode)
        }
        #endif
    }
    @State private var messages: [SessionMessage] = []
    @State private var previousCursor: String?
    @State private var isLoading = true
    @State private var isLoadingEarlier = false
    @State private var earlierError: String?
    @State private var errorMessage: String?
    @State private var didAutoScroll = false

    private let bottomAnchor = "session-mobile-bottom"

    private var session: Session {
        store.session(id: sessionID) ?? fallback
    }

    private var isRunning: Bool { store.isRunning(session) }
    private var project: String { store.projectName(for: session) }

    private var availableModes: [MobileStore.DetailMode] {
        var modes: [MobileStore.DetailMode] = [.conversation, .stats, .changes, .prompts]
        if mode == .subagents
            || store.hasSubagents(sessionID)
            || store.isLoadingSubagents(sessionID) {
            modes.append(.subagents)
        }
        return modes
    }

    private var refreshKey: String {
        "\(sessionID)-\(Int(session.time.updated))-\(isRunning)"
    }

    var body: some View {
        // Capture before the toolbar closure; bar items can be hosted without
        // the screen's environment objects.
        let running = isRunning

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    summary

                    Picker("View", selection: $mode) {
                        ForEach(availableModes) { mode in
                            Text(mode == .conversation ? "Chat" : mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    content

                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.first?.id) { _, _ in
                guard mode == .conversation || mode == .prompts,
                      !didAutoScroll, !messages.isEmpty
                else { return }
                didAutoScroll = true
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: mode) { _, newMode in
                guard newMode == .conversation || newMode == .prompts else { return }
                scrollToBottom(proxy, animated: false)
            }
        }
        .mobileScreenBackground()
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if running {
                    HStack(spacing: 5) {
                        PulsingDot(size: 7)
                        Text("Running")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.running)
                    }
                } else {
                    Chip(text: "Finished")
                }
            }
        }
        .task(id: refreshKey) {
            await loadLatest()
            if mode == .changes {
                await store.loadChanges(sessionID)
            } else if mode == .stats {
                await store.loadSessionStats(sessionID)
            }
        }
        .task(id: sessionID) {
            await store.loadSubagents(sessionID)
        }
        .task(id: mode) {
            switch mode {
            case .changes:
                await store.loadChanges(sessionID)
            case .stats:
                await store.loadSessionStats(sessionID)
            default:
                break
            }
        }
        .refreshable {
            await loadLatest()
            await store.loadSubagents(sessionID, force: true)
            if mode == .changes {
                await store.loadChanges(sessionID, force: true)
            } else if mode == .stats {
                await store.loadSessionStats(sessionID, force: true)
            }
            await store.refreshLive()
        }
        .onChange(of: availableModes, initial: true) { _, modes in
            if !modes.contains(mode) { mode = .conversation }
        }
    }

    // MARK: - Header

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(session.displayTitle)
                .font(.headline)
                .textSelection(.enabled)

            HStack(spacing: 5) {
                Text(project)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                if let model = session.model {
                    Chip(text: model.id)
                }
                if let agent = session.agent, !agent.isEmpty {
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

    private var durationLabel: String {
        if isRunning {
            return Fmt.elapsed(since: session.time.createdDate)
        }
        return Fmt.elapsed(since: session.time.createdDate, now: session.time.updatedDate)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
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
    private var stats: some View {
        let state = store.sessionStats[sessionID]
        if let state, state.isLoading && state.stats == nil {
            loading("Measuring this session…")
        } else if let state, let error = state.error, state.stats == nil {
            errorState(error, title: "Couldn't load stats")
        } else if let stats = state?.stats {
            MobileSessionStatsView(stats: stats)
        } else {
            loading("Loading stats…")
        }
    }

    @ViewBuilder
    private var changes: some View {
        let state = store.sessionChanges[sessionID]
        if let state, state.isLoading && state.changes.isEmpty {
            loading("Loading file changes…")
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
    private var conversation: some View {
        if isLoading && messages.isEmpty {
            loading("Loading conversation…")
        } else if let errorMessage, messages.isEmpty {
            errorState(errorMessage)
        } else if messages.isEmpty {
            EmptyState(
                icon: "bubble.left",
                title: "No messages yet",
                subtitle: "The conversation will appear as the model responds."
            )
        } else {
            if previousCursor != nil {
                loadEarlierButton
            }
            ForEach(Array(messages.reversed()), id: \.id) { message in
                MessageCard(message: message)
            }
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
        }
    }

    @ViewBuilder
    private var prompts: some View {
        let prompts = Array(messages.reversed().filter(\.isUserLike))
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
            if previousCursor != nil {
                loadEarlierButton
            }
            ForEach(Array(prompts.enumerated()), id: \.element.id) { index, message in
                PromptRow(index: index + 1, message: message)
            }
        }
    }

    @ViewBuilder
    private var subagents: some View {
        if let list = store.subagentList(for: sessionID) {
            if list.isLoading && list.sessions.isEmpty {
                loading("Loading subagents…")
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
                }

                if let error = list.error {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                }
            }
        } else {
            loading("Loading subagents…")
        }
    }

    // MARK: - Pieces

    private var loadEarlierButton: some View {
        VStack(spacing: 4) {
            Button {
                Task { await loadEarlier() }
            } label: {
                HStack(spacing: 5) {
                    if isLoadingEarlier {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.caption.weight(.bold))
                    }
                    Text(isLoadingEarlier ? "Loading…" : "Load earlier")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .disabled(isLoadingEarlier)

            if let earlierError {
                Text(earlierError)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func loading(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(message).font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String, title: String = "Couldn't load this session") -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Theme.warn)
            Text(title).font(.subheadline.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                Task { await loadLatest() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .card()
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 40_000_000)
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchor, anchor: .bottom)
            }
        }
    }

    // MARK: - Loading

    private func loadLatest() async {
        if messages.isEmpty { isLoading = true }
        defer { isLoading = false }

        do {
            let response = try await store.messages(for: sessionID, limit: 100)
            guard !Task.isCancelled else { return }
            let fresh = response.data
            let freshIDs = Set(fresh.map(\.id))
            let cutoff = fresh.map(\.time.created).min()
            let retained = messages.filter { message in
                guard !freshIDs.contains(message.id), let cutoff else { return false }
                return message.time.created < cutoff
            }

            messages = fresh + retained
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
            let response = try await store.messages(for: sessionID, limit: 100, cursor: cursor)
            guard !Task.isCancelled else { return }
            let existing = Set(messages.map(\.id))
            messages.append(contentsOf: response.data.filter { !existing.contains($0.id) })
            previousCursor = response.cursor?.previous
        } catch {
            guard !Task.isCancelled else { return }
            earlierError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

struct SubagentSessionRow: View {
    let session: Session
    let running: Bool
    var activity: SessionActivity?
    var descendants: Int = 0

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if running {
                PulsingDot(size: 7).padding(.top, 5)
            } else {
                Image(systemName: "person.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                if running, let activity {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ActivityLine(activity: activity, now: context.date)
                    }
                } else {
                    HStack(spacing: 5) {
                        if let model = session.model { Chip(text: model.id) }
                        Text(Fmt.relative(from: session.time.updatedDate))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 10) {
                    if session.cost > 0 {
                        Text(Fmt.usd(session.cost)).foregroundStyle(Theme.accent)
                    }
                    Text(Fmt.compact(session.tokens.generated) + " tok")
                    if descendants > 0 {
                        Label("\(descendants)", systemImage: "person.2.fill")
                            .foregroundStyle(Theme.reasoning)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 3)
        }
        .card(padding: 11)
    }
}
