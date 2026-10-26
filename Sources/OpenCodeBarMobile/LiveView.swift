import SwiftUI

struct LiveView: View {
    @EnvironmentObject var settings: HubSettingsStore
    @EnvironmentObject var store: MobileStore
    @EnvironmentObject var router: MobileRouter
    @State private var path = NavigationPath()
    @State private var showingNewSession = false
    @State private var sessionToOpen: Session?
    @State var selectedProjectID: String?
    @State var timeFilter: SessionTimeFilter = .all
    @State var statusFilter: SessionStatusFilter = .all
    @State var groupedByTime = false
    @State private var recentLimit = LiveView.recentPageSize
    @State private var scrollToTopTrigger = 0
    @State private var deepLinkAttempt = ""
    @State private var pauseTarget: Session?
    @State private var controlError: String?

    private let topAnchor = "live-top"

    var body: some View {
        let connection = store.connection
        let activeCount = store.activeCount

        return NavigationStack(path: $path) {
            Group {
                if !settings.isConfigured {
                    ScrollView {
                        SetupPrompt()
                            .padding(16)
                    }
                } else {
                    content
                }
            }
            .mobileScreenBackground()
            .navigationTitle("OpenCode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        scrollToTopTrigger += 1
                    } label: {
                        MobileBrandTitle()
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scroll to top")
                    .accessibilityHint("Scrolls the session list to the top")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingNewSession = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .disabled(!settings.isConfigured)
                    .accessibilityLabel("New session")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ConnectionPill(connection: connection, activeCount: activeCount)
                }
            }
            .refreshable { await store.refreshAll() }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(
                    sessionID: session.id,
                    fallback: session,
                    onOpenSession: { path.append($0) }
                )
            }
            .task(id: store.lastUpdated) {
                openRequestedSession()
            }
            .onChange(of: router.requestedSessionID) { _, _ in
                openRequestedSession()
            }
            .onAppear {
                openRequestedSession()
            }
            .sheet(isPresented: $showingNewSession, onDismiss: openCreatedSession) {
                MobileNewSessionSheet { session in
                    sessionToOpen = session
                }
                .environmentObject(store)
            }
            .sheet(item: $pauseTarget) { session in
                PauseSessionSheet(sessionTitle: session.displayTitle) { until in
                    try await store.pauseSession(session, until: until)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .alert("Session control failed", isPresented: controlErrorBinding) {
                Button("OK") { controlError = nil }
            } message: {
                Text(controlError ?? "")
            }
        }
    }

    private func openCreatedSession() {
        guard let session = sessionToOpen else { return }
        sessionToOpen = nil
        path.append(session)
    }

    /// Handles links from widgets (`opencodebar://session/<id>`) as well as the
    /// debug launch hook used for screenshots. If the session is not in the
    /// cached window, fetch it before pushing the detail screen.
    private func openRequestedSession() {
        guard path.isEmpty else { return }

        #if DEBUG
        if let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_OPEN_SESSION"] {
            if requested == "running" {
                if let first = store.runningSessions.first { path.append(first) }
            } else if let match = store.session(id: requested) {
                path.append(match)
            }
            return
        }
        #endif

        guard let requested = router.requestedSessionID,
              requested != deepLinkAttempt
        else { return }

        deepLinkAttempt = requested
        if let match = store.session(id: requested) {
            router.requestedSessionID = nil
            deepLinkAttempt = ""
            path.append(match)
            return
        }

        Task {
            guard let fetched = await store.fetchSession(id: requested) else { return }
            router.requestedSessionID = nil
            deepLinkAttempt = ""
            if path.isEmpty { path.append(fetched) }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Lazy so "Show more" and a long running list only build the
                // rows on screen. Running rows use TimelineView per row, so a
                // tick does not invalidate the whole feed.
                LazyVStack(alignment: .leading, spacing: 16) {
                    Color.clear.frame(height: 1).id(topAnchor)

                    if case .offline(let reason) = store.connection {
                        NoticeRow(icon: "wifi.exclamationmark", message: reason, tint: Theme.warn)
                    }

                    runningSection
                    recentSection

                    if let updated = store.lastUpdated {
                        Text("Updated \(Fmt.relative(from: updated))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .onChange(of: activeProjectID) { _, _ in recentLimit = Self.recentPageSize }
            .onChange(of: timeFilter) { _, _ in recentLimit = Self.recentPageSize }
            .onChange(of: statusFilter) { _, _ in recentLimit = Self.recentPageSize }
            .onChange(of: scrollToTopTrigger) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(topAnchor, anchor: .top)
                }
            }
        }
    }

    private var runningSection: some View {
        let sessions = store.runningSessions
        let ids = sessions.map(\.id)

        return LazyVStack(alignment: .leading, spacing: 8) {
            SectionHeader("Running") {
                Text("\(store.runningSessions.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(store.runningSessions.isEmpty ? Color.secondary : Theme.running)
            }

            if sessions.isEmpty {
                if store.isInitialLoading {
                    SessionListSkeleton(count: 2, showsActivity: true)
                        .shimmering()
                } else {
                    EmptyState(
                        icon: "moon.zzz.fill",
                        title: "No active sessions",
                        subtitle: "Sessions appear here the moment they start."
                    )
                    .transition(.opacity)
                }
            } else {
                ForEach(sessions) { session in
                    NavigationLink(value: session) {
                        RunningSessionRow(
                            session: session,
                            project: store.projectName(for: session),
                            activity: store.activity(for: session.id),
                            subagents: store.activeSubagentCount(for: session.id)
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.recentInsertion)
                    .contextMenu {
                        if store.isRunning(session) || session.isHeld {
                            controlMenu(for: session)
                        }
                    }
                }
            }
        }
        .animateRecentInsertion(ids: ids)
    }

    private var recentSection: some View {
        let sessions = Array(filteredRecent.prefix(recentLimit))
        let ids = sessions.map(\.id)
        let remaining = filteredRecent.count - sessions.count

        return LazyVStack(alignment: .leading, spacing: 8) {
            SectionHeader("Recent") {
                HStack(spacing: 6) {
                    projectFilterMenu
                    timeFilterMenu
                    statusFilterMenu
                    groupingToggle
                }
            }

            if sessions.isEmpty {
                if store.isInitialLoading {
                    SessionListSkeleton(count: 4)
                        .shimmering()
                } else {
                    EmptyState(
                        icon: filtersActive ? "line.3.horizontal.decrease.circle" : "clock",
                        title: filtersActive ? "No matching sessions" : "No recent sessions",
                        subtitle: filtersActive
                            ? "Try another project, date range, or status."
                            : "Your session history will show up here."
                    )
                    .transition(.opacity)
                }
            } else if groupedByTime {
                ForEach(SessionGrouping.groupByTime(sessions)) { section in
                    LazyVStack(alignment: .leading, spacing: 8) {
                        groupHeader(section.group.title)
                        ForEach(section.sessions) { session in
                            recentLink(session)
                        }
                    }
                }
            } else {
                ForEach(sessions) { session in
                    recentLink(session)
                }
            }

            if remaining > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        recentLimit += Self.recentPageSize
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                        Text("Show \(min(remaining, Self.recentPageSize)) more")
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
                .accessibilityLabel("Show more recent sessions")
            }
        }
        .animateRecentInsertion(ids: ids)
    }

    private static let recentPageSize = 20

    private func recentLink(_ session: Session) -> some View {
        NavigationLink(value: session) {
            RecentSessionRow(
                session: session,
                project: store.projectName(for: session)
            )
        }
        .buttonStyle(.plain)
        .transition(.recentInsertion)
        .contextMenu {
            if store.isRunning(session) || session.isHeld {
                controlMenu(for: session)
            }
        }
    }

    @ViewBuilder
    private func controlMenu(for session: Session) -> some View {
        if session.isHeld {
            Button {
                runControl { try await store.continueSession(session) }
            } label: {
                Label("Continue", systemImage: "play.fill")
            }
            Divider()
        }
        Button {
            pauseTarget = session
        } label: {
            Label(session.isPaused ? "Change pause…" : "Pause…", systemImage: "pause.circle")
        }
        Button(role: .destructive) {
            runControl { try await store.stopSession(session) }
        } label: {
            Label("Stop", systemImage: "stop.circle")
        }
    }

    private func runControl(_ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                controlError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private var controlErrorBinding: Binding<Bool> {
        Binding(
            get: { controlError != nil },
            set: { if !$0 { controlError = nil } }
        )
    }

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(.tertiary)
            .padding(.leading, 2)
            .padding(.top, 2)
    }

}
