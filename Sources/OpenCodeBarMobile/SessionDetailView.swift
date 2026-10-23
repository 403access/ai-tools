import SwiftUI
import UIKit

/// Mobile session detail: live header, conversation, prompts, and subagents.
struct SessionDetailView: View {
    @EnvironmentObject var store: MobileStore
    let sessionID: String
    let fallback: Session

    @State var mode: MobileStore.DetailMode = .conversation

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
    @State var messages: [SessionMessage] = []
    @State var previousCursor: String?
    @State var isLoading = true
    @State var isLoadingEarlier = false
    @State var isFetchingLatest = false
    @State var loadedRemotePage = false
    @State var earlierError: String?
    @State var errorMessage: String?
    @State var didAutoScroll = false
    @State var draft = ""
    @State var isSending = false
    @State var sendError: String?
    @State var pendingError: String?
    @State var cancellingPending: Set<String> = []
    @State var scrollRequest = 0
    @StateObject var dictation = SpeechDictation()
    @FocusState var composerFocused: Bool

    let topAnchor = "session-mobile-top"

    var session: Session {
        store.session(id: sessionID) ?? fallback
    }

    var isRunning: Bool { store.isRunning(session) }
    var project: String { store.projectName(for: session) }

    var availableModes: [MobileStore.DetailMode] {
        var modes: [MobileStore.DetailMode] = [.conversation, .stats, .changes, .prompts]
        if mode == .subagents
            || store.hasSubagents(sessionID)
            || store.isLoadingSubagents(sessionID) {
            modes.append(.subagents)
        }
        return modes
    }

    var refreshKey: String {
        "\(sessionID)-\(Int(session.time.updated))-\(isRunning)"
    }

    var body: some View {
        // Capture before the toolbar closure; bar items can be hosted without
        // the screen's environment objects.
        let running = isRunning

        return ScrollViewReader { proxy in
            ScrollView {
                // Keep the page itself eager; the message list below is lazy.
                // The running summary updates every second, and a lazy outer
                // stack can otherwise disturb the scroll position while it does.
                VStack(alignment: .leading, spacing: 12) {
                    // Anchor at the very top so scrolling to it keeps the
                    // summary header visible (the Mac panel does the same).
                    Color.clear.frame(height: 1).id(topAnchor)

                    summary

                    Picker("View", selection: $mode) {
                        ForEach(availableModes) { mode in
                            Text(mode == .conversation ? "Chat" : mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.first?.id) { _, newID in
                // Show the newest message the first time content loads.
                guard !didAutoScroll, newID != nil,
                      mode == .conversation || mode == .prompts
                else { return }
                didAutoScroll = true
                scrollToTop(proxy, animated: false)
            }
            .onChange(of: mode) { _, newMode in
                guard newMode == .conversation || newMode == .prompts else { return }
                scrollToTop(proxy, animated: false)
            }
            .onChange(of: scrollRequest) { _, _ in
                scrollToTop(proxy, animated: true)
            }
            .onAppear {
                // A pushed screen can briefly inherit the previous scroll
                // offset; re-assert the top so the summary stays visible.
                scrollToTop(proxy, animated: false)
            }
        }
        .mobileScreenBackground()
        .onDisappear { dictation.cancel() }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if mode == .conversation {
                VStack(spacing: 0) {
                    pendingQueue
                    composer
                }
            }
        }
        .navigationTitle(session.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    scrollRequest += 1
                } label: {
                    Text(session.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scroll to top")
                .accessibilityHint("Scrolls the conversation to the top")
            }
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
            if mode == .conversation || mode == .prompts {
                await loadLatest()
            }
            if mode == .conversation {
                await store.loadPending(sessionID)
            }
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
            case .conversation, .prompts:
                if messages.isEmpty { await loadLatest() }
                if mode == .conversation { await store.loadPending(sessionID) }
            case .changes:
                await store.loadChanges(sessionID)
            case .stats:
                await store.loadSessionStats(sessionID)
            case .subagents:
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
}
