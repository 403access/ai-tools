import SwiftUI

struct LiveView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @State private var path = NavigationPath()
    @State private var showingNewSession = false
    @State private var sessionToOpen: Session?
    @State private var selectedProjectID: String?
    @State private var timeFilter: SessionTimeFilter = .all
    @State private var groupedByTime = false

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
                    MobileBrandTitle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Button {
                            showingNewSession = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .disabled(!settings.isConfigured)
                        .accessibilityLabel("New session")

                        ConnectionPill(connection: connection, activeCount: activeCount)
                    }
                }
            }
            .refreshable { await store.refreshAll() }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(sessionID: session.id, fallback: session)
            }
            .task(id: store.lastUpdated) {
                openRequestedSession()
            }
            .sheet(isPresented: $showingNewSession, onDismiss: openCreatedSession) {
                MobileNewSessionSheet { session in
                    sessionToOpen = session
                }
                .environmentObject(store)
            }
        }
    }

    private func openCreatedSession() {
        guard let session = sessionToOpen else { return }
        sessionToOpen = nil
        path.append(session)
    }

    #if DEBUG
    /// Opens a session on launch for screenshot tooling:
    /// `SIMCTL_CHILD_OPENCODEBAR_OPEN_SESSION=running` or a session id.
    private func openRequestedSession() {
        guard path.isEmpty,
              let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_OPEN_SESSION"]
        else { return }
        if requested == "running" {
            if let first = store.runningSessions.first { path.append(first) }
        } else if let match = store.session(id: requested) {
            path.append(match)
        }
    }
    #else
    private func openRequestedSession() {}
    #endif

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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
    }

    private var runningSection: some View {
        let sessions = store.runningSessions
        let ids = sessions.map(\.id)

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Running") {
                Text("\(store.runningSessions.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(store.runningSessions.isEmpty ? Color.secondary : Theme.running)
            }

            if sessions.isEmpty {
                EmptyState(
                    icon: "moon.zzz.fill",
                    title: "No active sessions",
                    subtitle: "Sessions appear here the moment they start."
                )
                .transition(.opacity)
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
                }
            }
        }
        .animateRecentInsertion(ids: ids)
    }

    private var recentSection: some View {
        let sessions = Array(filteredRecent.prefix(30))
        let ids = sessions.map(\.id)

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Recent") {
                HStack(spacing: 6) {
                    projectFilterMenu
                    timeFilterMenu
                    groupingToggle
                }
            }

            if sessions.isEmpty {
                EmptyState(
                    icon: filtersActive ? "line.3.horizontal.decrease.circle" : "clock",
                    title: filtersActive ? "No matching sessions" : "No recent sessions",
                    subtitle: filtersActive
                        ? "Try another project or date range."
                        : "Your session history will show up here."
                )
                .transition(.opacity)
            } else if groupedByTime {
                ForEach(SessionGrouping.groupByTime(sessions)) { section in
                    VStack(alignment: .leading, spacing: 8) {
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
        }
        .animateRecentInsertion(ids: ids)
    }

    private func recentLink(_ session: Session) -> some View {
        NavigationLink(value: session) {
            RecentSessionRow(
                session: session,
                project: store.projectName(for: session)
            )
        }
        .buttonStyle(.plain)
        .transition(.recentInsertion)
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

    private var groupingToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                groupedByTime.toggle()
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(groupedByTime ? Theme.accent : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(
                        groupedByTime
                            ? Theme.accent.opacity(0.14)
                            : Color.primary.opacity(0.07)
                    )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Group recent sessions by date")
        .accessibilityValue(groupedByTime ? "On" : "Off")
        .accessibilityAddTraits(groupedByTime ? .isSelected : [])
    }

    private var activeProjectID: String? {
        guard let selectedProjectID, store.projects[selectedProjectID] != nil else {
            return nil
        }
        return selectedProjectID
    }

    private var filteredRecent: [Session] {
        SessionFiltering.apply(
            to: store.recentSessions,
            projectID: activeProjectID,
            time: timeFilter,
            projects: store.projects
        )
    }

    /// Projects that have recent sessions, so the menu stays relevant.
    private var filterProjects: [Project] {
        let recent = store.recentSessions
        return store.orderedProjects.filter { project in
            recent.contains {
                SessionFiltering.matchesProject(
                    $0,
                    projectID: project.id,
                    projects: store.projects
                )
            }
        }
    }

    private var selectedProjectName: String {
        guard let activeProjectID else { return "All projects" }
        return store.projects[activeProjectID]?.displayName
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
        .accessibilityLabel("Filter by date")
        .accessibilityValue(timeFilter.title)
    }

    private func filterChip(icon: String, title: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
        .contentShape(Capsule())
    }
}

struct RunningSessionRow: View {
    let session: Session
    let project: String
    var activity: SessionActivity?
    var subagents: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 9) {
                PulsingDot(size: 8)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 6) {
                        Text(session.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text(Fmt.elapsed(since: session.time.createdDate, now: context.date))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .fixedSize()
                    }

                    if let activity {
                        ActivityLine(activity: activity, now: context.date)
                        if !activity.todos.isEmpty {
                            TodoProgressRow(activity: activity)
                        }
                    } else {
                        HStack(spacing: 5) {
                            ProgressView().controlSize(.small)
                            Text("Working")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

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
                        if session.cost > 0 {
                            Label(Fmt.usd(session.cost), systemImage: "dollarsign.circle")
                                .foregroundStyle(Theme.accent)
                        }
                        Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                        if subagents > 0 {
                            Label("\(subagents)", systemImage: "person.2.fill")
                                .foregroundStyle(Theme.reasoning)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 5)
            }
            .card(padding: 12)
        }
    }
}

struct RecentSessionRow: View {
    let session: Session
    let project: String

    var body: some View {
        HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 5) {
                    Text(project)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    if let model = session.model {
                        Chip(text: model.id)
                    }
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.relative(from: session.time.updatedDate))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
                Text(Fmt.compact(session.tokens.generated) + " tok")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 12)
    }
}
