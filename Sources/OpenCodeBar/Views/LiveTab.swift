import SwiftUI

struct LiveTab: View {
    @EnvironmentObject var state: AppState
    @State private var showingNewSession = false
    @State private var selectedProjectID: String?
    @State private var timeFilter: SessionTimeFilter = .all
    @State private var groupedByTime = false
    @State private var recentLimit = LiveTab.recentPageSize
    @State private var pauseTarget: Session?
    @State private var controlError: String?

    var body: some View {
        let running = state.runningSessions
        let recent = Array(filteredRecent.prefix(recentLimit))
        let isLoading = state.isInitialLoading

        return VStack(alignment: .leading, spacing: 14) {
            LazyVStack(alignment: .leading, spacing: 8) {
                SectionHeader("Running") {
                    HStack(spacing: 7) {
                        Text("\(running.count)")
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(running.isEmpty ? .secondary : Theme.running)

                        Button {
                            showingNewSession = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                                Text("New")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Theme.accent.opacity(0.14))
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .help("Start a new session")
                        .accessibilityLabel("New session")
                    }
                }

                if isLoading && running.isEmpty {
                    SessionListSkeleton(count: 2, showsActivity: true)
                        .shimmering()
                } else if running.isEmpty {
                    EmptyState(
                        icon: "moon.zzz.fill",
                        title: "No active sessions",
                        subtitle: "Sessions appear here the moment they start."
                    )
                    .transition(.opacity)
                } else {
                    ForEach(running) { session in
                        runningButton(session)
                    }
                }
            }
            .animateRecentInsertion(ids: running.map(\.id))

            LazyVStack(alignment: .leading, spacing: 8) {
                SectionHeader("Recent") {
                    HStack(spacing: 5) {
                        projectFilterMenu
                        timeFilterMenu
                        groupingToggle
                    }
                }

                if isLoading && recent.isEmpty {
                    SessionListSkeleton(count: 4)
                        .shimmering()
                } else if recent.isEmpty {
                    EmptyState(
                        icon: filtersActive ? "line.3.horizontal.decrease.circle" : "clock",
                        title: filtersActive ? "No matching sessions" : "No recent sessions",
                        subtitle: filtersActive
                            ? "Try another project or date range."
                            : "Your session history will show up here."
                    )
                    .transition(.opacity)
                } else if groupedByTime {
                    ForEach(SessionGrouping.groupByTime(recent)) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            groupHeader(section.group.title)
                            ForEach(section.sessions) { session in
                                recentButton(session)
                            }
                        }
                    }

                    if filteredRecent.count > recentLimit {
                        showMoreButton(remaining: filteredRecent.count - recentLimit)
                    }
                } else {
                    ForEach(recent) { session in
                        recentButton(session)
                    }

                    if filteredRecent.count > recentLimit {
                        showMoreButton(remaining: filteredRecent.count - recentLimit)
                    }
                }
            }
            .animateRecentInsertion(ids: recent.map(\.id))
        }
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet()
                .environmentObject(state)
        }
        .sheet(item: $pauseTarget) { session in
            PauseSessionSheet(sessionTitle: session.displayTitle) { until in
                try await state.pauseSession(session, until: until)
            }
        }
        .alert("Session control failed", isPresented: controlErrorBinding) {
            Button("OK") { controlError = nil }
        } message: {
            Text(controlError ?? "")
        }
        .onChange(of: activeProjectID) { _, _ in recentLimit = Self.recentPageSize }
        .onChange(of: timeFilter) { _, _ in recentLimit = Self.recentPageSize }
    }

    private static let recentPageSize = 20

    private var controlErrorBinding: Binding<Bool> {
        Binding(
            get: { controlError != nil },
            set: { if !$0 { controlError = nil } }
        )
    }

    /// Reveals the next page of recent rows. The data is already in memory; this
    /// keeps the initial render (and its view tree) small.
    private func showMoreButton(remaining: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                recentLimit += Self.recentPageSize
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                Text(remaining > 0 ? "Show \(min(remaining, Self.recentPageSize)) more" : "Show more")
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .help("Show more recent sessions")
    }

    private func recentButton(_ session: Session) -> some View {
        rowButton(session) {
            RecentRow(session: session, project: state.projectName(for: session))
        }
    }

    private func runningButton(_ session: Session) -> some View {
        rowButton(session) {
            RunningRow(
                session: session,
                project: state.projectName(for: session),
                activity: state.activity(for: session.id),
                subagents: state.activeSubagentCount(for: session.id)
            )
        }
    }

    /// A row that opens the session and, when it is running or held, offers
    /// pause, stop, and continue from the context menu.
    @ViewBuilder
    private func rowButton<Content: View>(
        _ session: Session,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            state.open(session)
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Show conversation and prompts")
        .transition(.recentInsertion)
        .contextMenu {
            if state.isRunning(session) || session.isHeld {
                sessionControlMenu(for: session)
            }
        }
    }

    @ViewBuilder
    private func sessionControlMenu(for session: Session) -> some View {
        if session.isHeld {
            Button {
                runControl { try await state.continueSession(session) }
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
            runControl { try await state.stopSession(session) }
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

    private func groupHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .foregroundStyle(.tertiary)
            .padding(.leading, 2)
            .padding(.top, 2)
    }

    private var groupingToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                groupedByTime.toggle()
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(groupedByTime ? Theme.accent : Color.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(
                        groupedByTime ? Theme.accent.opacity(0.14) : Color.clear
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(
            groupedByTime
                ? "Show recent sessions as one list"
                : "Group recent sessions by date"
        )
        .accessibilityLabel("Group recent sessions by date")
        .accessibilityValue(groupedByTime ? "On" : "Off")
        .accessibilityAddTraits(groupedByTime ? .isSelected : [])
    }

    private var activeProjectID: String? {
        guard let selectedProjectID, state.projects[selectedProjectID] != nil else {
            return nil
        }
        return selectedProjectID
    }

    private var filteredRecent: [Session] {
        SessionFiltering.apply(
            to: state.recentSessions,
            projectID: activeProjectID,
            time: timeFilter,
            projects: state.projects
        )
    }

    /// Projects that have recent sessions, so the menu stays relevant.
    private var filterProjects: [Project] {
        let recent = state.recentSessions
        return state.orderedProjects.filter { project in
            recent.contains {
                SessionFiltering.matchesProject(
                    $0,
                    projectID: project.id,
                    projects: state.projects
                )
            }
        }
    }

    private var selectedProjectName: String {
        guard let activeProjectID else { return "All projects" }
        return state.projects[activeProjectID]?.displayName
            ?? filterProjects.first { $0.id == activeProjectID }?.displayName
            ?? "All projects"
    }

    private var filtersActive: Bool {
        activeProjectID != nil || timeFilter != .all
    }

    private var projectFilterMenu: some View {
        Menu {
            Button {
                selectedProjectID = nil
            } label: {
                if activeProjectID == nil {
                    Label("All projects", systemImage: "checkmark")
                } else {
                    Text("All projects")
                }
            }

            if !filterProjects.isEmpty {
                Divider()
            }

            ForEach(filterProjects) { project in
                Button {
                    selectedProjectID = project.id
                } label: {
                    if activeProjectID == project.id {
                        Label(project.displayName, systemImage: "checkmark")
                    } else {
                        Text(project.displayName)
                    }
                }
            }
        } label: {
            filterChip(icon: "folder", title: selectedProjectName)
        }
        .fixedSize()
        .controlSize(.small)
        .help("Filter by project")
        .accessibilityLabel("Filter by project")
        .accessibilityValue(selectedProjectName)
    }

    private var timeFilterMenu: some View {
        Menu {
            ForEach(SessionTimeFilter.allCases) { option in
                Button {
                    timeFilter = option
                } label: {
                    if option == timeFilter {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            filterChip(icon: "calendar", title: timeFilter.shortTitle)
        }
        .fixedSize()
        .controlSize(.small)
        .help("Filter by date")
        .accessibilityLabel("Filter by date")
        .accessibilityValue(timeFilter.title)
    }

    private func filterChip(icon: String, title: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.secondary)
    }
}
