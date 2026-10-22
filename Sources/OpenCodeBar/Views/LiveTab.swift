import SwiftUI

struct LiveTab: View {
    @EnvironmentObject var state: AppState
    @State private var showingNewSession = false
    @State private var selectedProjectID: String?
    @State private var timeFilter: SessionTimeFilter = .all
    @State private var groupedByTime = false

    var body: some View {
        let running = state.runningSessions
        let recent = Array(filteredRecent.prefix(20))

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
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

                if running.isEmpty {
                    EmptyState(
                        icon: "moon.zzz.fill",
                        title: "No active sessions",
                        subtitle: "Sessions appear here the moment they start."
                    )
                    .transition(.opacity)
                } else {
                    ForEach(running) { session in
                        Button {
                            state.open(session)
                        } label: {
                            RunningRow(
                                session: session,
                                project: state.projectName(for: session),
                                activity: state.activity(for: session.id),
                                subagents: state.activeSubagentCount(for: session.id)
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .help("Show conversation and prompts")
                        .transition(.recentInsertion)
                    }
                }
            }
            .animateRecentInsertion(ids: running.map(\.id))

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Recent") {
                    HStack(spacing: 5) {
                        projectFilterMenu
                        timeFilterMenu
                        groupingToggle
                    }
                }

                if recent.isEmpty {
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
                } else {
                    ForEach(recent) { session in
                        recentButton(session)
                    }
                }
            }
            .animateRecentInsertion(ids: recent.map(\.id))
        }
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet()
                .environmentObject(state)
        }
    }

    private func recentButton(_ session: Session) -> some View {
        Button {
            state.open(session)
        } label: {
            RecentRow(session: session, project: state.projectName(for: session))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Show conversation and prompts")
        .transition(.recentInsertion)
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

struct RunningRow: View {
    let session: Session
    let project: String
    var activity: SessionActivity?
    var subagents: Int = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(alignment: .top, spacing: 10) {
                PulsingDot(size: 8)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if let activity {
                        ActivityLine(activity: activity, now: context.date)
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text("Working")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 4)
                            Text(Fmt.elapsed(since: session.time.createdDate, now: context.date))
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        }
                    }

                    HStack(spacing: 5) {
                        Text(project)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                        if let model = session.model {
                            Chip(text: model.id)
                                .help(model.label)
                        }
                        if let agent = session.agent, !agent.isEmpty {
                            Chip(text: agent, systemImage: "person.fill", tint: Theme.reasoning)
                        }
                        if subagents > 0 {
                            Chip(
                                text: subagents == 1 ? "1 agent" : "\(subagents) agents",
                                systemImage: "person.2.fill",
                                tint: Theme.reasoning
                            )
                            .help(subagents == 1 ? "1 running subagent" : "\(subagents) running subagents")
                        }
                    }

                    if let activity, !activity.todos.isEmpty {
                        TodoProgressRow(activity: activity)
                    }

                    HStack(spacing: 10) {
                        Label(Fmt.elapsed(since: session.time.createdDate, now: context.date), systemImage: "timer")
                        if session.cost > 0 {
                            Text(Fmt.usd(session.cost))
                                .foregroundStyle(Theme.accent)
                        }
                        Label(Fmt.compact(session.tokens.generated) + " tok", systemImage: "text.word.spacing")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .card()
        }
    }
}

struct RecentRow: View {
    let session: Session
    let project: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(project)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    if let model = session.model {
                        Chip(text: model.id)
                    }
                    Text(Fmt.relative(from: session.time.updatedDate))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 3) {
                if session.cost > 0 {
                    Text(Fmt.usd(session.cost))
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("free")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(Fmt.compact(session.tokens.generated) + " tok")
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 10)
    }
}
