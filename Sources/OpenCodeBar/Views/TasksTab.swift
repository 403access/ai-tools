import SwiftUI

/// Project-management board for sessions. New top-level sessions become tasks,
/// running ones are in progress, and finished ones wait in review until the
/// user accepts them or sends another prompt.
///
/// The menu bar panel and the narrow desktop split show a filtered list. A wide
/// desktop window switches to a board with one column per status, so resizing
/// the window reflows the tasks instead of stretching single cards across the
/// screen.
struct TasksTab: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: TaskBoardFilter = .review
    @State private var selectedProjectID: String?
    @State private var timeFilter: SessionTimeFilter = .all
    @State private var statusFilter: SessionStatusFilter = .all
    @State private var showingNewSession = false
    /// Measured content width, so the layout can follow window resizing.
    @State private var availableWidth: CGFloat = 0
    /// Done tasks are reference only, so they stay out of the board until the
    /// user asks for them.
    @AppStorage("tasks.showDone") private var showDone = false
    /// How each board column is split. Date grouping can stand alone or be
    /// combined with project grouping, in which case date comes first.
    @AppStorage("tasks.grouping") private var groupingRaw = ""
    /// Bucket size for date grouping, also remembered between launches.
    @AppStorage("tasks.dateInterval") private var dateIntervalRaw = "day"

    /// A status column stays readable at this width. The board needs room for
    /// three columns before it replaces the list; showing Done adds a fourth
    /// column that scrolls horizontally when the window is not wide enough.
    private let columnMinWidth: CGFloat = 230
    private let columnSpacing: CGFloat = 10

    private let sectionOrder: [SessionTask.Status] = [
        .queued, .review, .working, .done, .dismissed,
    ]

    private var visibleSections: [SessionTask.Status] {
        sectionOrder.filter { showDone || $0 != .done }
    }

    /// Columns shown on the wide board. Dismissed tasks stay in the list, where
    /// the All filter keeps them available for reference.
    private var boardOrder: [SessionTask.Status] {
        [.queued, .review, .working] + (showDone ? [.done] : [])
    }

    private var boardMinWidth: CGFloat {
        columnMinWidth * 3 + columnSpacing * 2
    }

    /// A board of empty columns is not useful; with only dismissed or hidden
    /// done tasks the filtered list carries the empty state instead.
    private var hasBoardContent: Bool {
        filteredTasks.contains { session in
            session.taskStatus.map(boardOrder.contains) ?? false
        }
    }

    private var activeProjectID: String? {
        guard let selectedProjectID, state.projects[selectedProjectID] != nil else {
            return nil
        }
        return selectedProjectID
    }

    /// The board after the project, date, and outcome filters have been applied.
    /// Task-status filters narrow this further in the list or board columns.
    private var filteredTasks: [Session] {
        let filtered = SessionFiltering.apply(
            to: state.tasks,
            projectID: activeProjectID,
            time: timeFilter,
            status: statusFilter,
            projects: state.projects
        )
        guard statusFilter == .finished else { return filtered }
        // The shared filter treats a session without a failure as finished.
        // Tasks that have not run yet are still "open" on the board.
        return filtered.filter {
            $0.taskStatus != .working && $0.taskStatus != .queued
        }
    }

    /// Projects that have tasks, so the menu stays relevant.
    private var filterProjects: [Project] {
        let tasks = state.tasks
        return state.orderedProjects.filter { project in
            tasks.contains {
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

    private var usesBoard: Bool {
        availableWidth >= boardMinWidth && hasBoardContent
    }

    /// Five filter chips get too tight in the desktop's narrow split column.
    private var usesScrollableFilters: Bool {
        availableWidth < 340
    }

    /// Board grouping modes. Date grouping can be combined with projects; the
    /// date bucket is always the outer level so one day's work stays together.
    private enum TaskGrouping: String, CaseIterable, Identifiable, Hashable {
        case none
        case project
        case date
        case dateAndProject

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            case .project: return "Project"
            case .date: return "Date"
            case .dateAndProject: return "Date and project"
            }
        }
    }

    private enum TaskDateInterval: String, CaseIterable, Identifiable, Hashable {
        case day
        case week
        case month

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "Day"
            case .week: return "Week"
            case .month: return "Month"
            }
        }
    }

    private struct ProjectTaskGroup: Identifiable {
        let id: String
        let name: String
        let sessions: [Session]
    }

    private struct DateTaskGroup: Identifiable {
        /// Start of the bucket, used as the identity so a group keeps its place
        /// while its cards update.
        let id: Date
        let title: String
        let sessions: [Session]
    }

    private var grouping: TaskGrouping {
        TaskGrouping(rawValue: groupingRaw) ?? .none
    }

    private var groupingBinding: Binding<TaskGrouping> {
        Binding(
            get: { grouping },
            set: { groupingRaw = $0.rawValue }
        )
    }

    private var dateInterval: TaskDateInterval {
        TaskDateInterval(rawValue: dateIntervalRaw) ?? .day
    }

    private var dateIntervalBinding: Binding<TaskDateInterval> {
        Binding(
            get: { dateInterval },
            set: { dateIntervalRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = state.tasksError, state.tasks.isEmpty {
                NoticeRow(icon: "exclamationmark.triangle", message: error, tint: Theme.warn)
            }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(widthReader)
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet()
                .environmentObject(state)
        }
        .task { await state.refreshTasks() }
        .onAppear { migrateLegacyGrouping() }
        .onChange(of: showDone) { _, visible in
            if !visible, filter == .done { filter = .review }
        }
    }

    /// The first board grouping release only had a By project toggle. Fold that
    /// preference into the new mode picker once, then drop the old key.
    private func migrateLegacyGrouping() {
        guard groupingRaw.isEmpty else { return }
        let legacy = UserDefaults.standard.bool(forKey: "tasks.groupByProject")
        groupingRaw = legacy ? TaskGrouping.project.rawValue : TaskGrouping.none.rawValue
        UserDefaults.standard.removeObject(forKey: "tasks.groupByProject")
    }

    /// Reports the width the tab can actually use. The panel and the desktop
    /// split pass a narrow column; a wide desktop window passes the full area.
    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { availableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in
                    availableWidth = width
                }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            sessionFilterRow

            // The wide board shows every status at once, so the status filters
            // would have nothing to narrow down.
            if !usesBoard {
                filterRow
            }

            HStack(spacing: 6) {
                Text("Auto-labelled from the request")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                groupMenu
                doneToggle
                newTaskButton
            }
        }
    }

    /// Project, date, and outcome filters carried over from the retired Live
    /// tab. They narrow the board as well as the list.
    private var sessionFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                projectFilterMenu
                timeFilterMenu
                statusFilterMenu
            }
        }
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
            filterChip(icon: "folder", title: selectedProjectName, active: activeProjectID != nil)
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
            filterChip(icon: "calendar", title: timeFilter.shortTitle, active: timeFilter != .all)
        }
        .fixedSize()
        .controlSize(.small)
        .help("Filter by date")
        .accessibilityLabel("Filter by date")
        .accessibilityValue(timeFilter.title)
    }

    private var statusFilterMenu: some View {
        Menu {
            ForEach(SessionStatusFilter.allCases) { option in
                Button {
                    statusFilter = option
                } label: {
                    if option == statusFilter {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            filterChip(icon: "flag", title: statusFilter.shortTitle, active: statusFilter != .all)
        }
        .fixedSize()
        .controlSize(.small)
        .help("Filter by status")
        .accessibilityLabel("Filter by status")
        .accessibilityValue(statusFilter.title)
    }

    private func filterChip(icon: String, title: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .bold))
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(
                active ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.06)
            )
        )
        .foregroundStyle(active ? Theme.accent : Color.secondary)
    }

    @ViewBuilder
    private var filterRow: some View {
        if usesScrollableFilters {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) { filterButtons }
            }
        } else {
            HStack(spacing: 6) { filterButtons }
        }
    }

    private var filterButtons: some View {
        ForEach(TaskBoardFilter.allCases) { option in
            if option != .done || showDone {
                ChoiceChip(
                    title: "\(option.shortTitle) \(count(for: option))",
                    isSelected: filter == option
                ) {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        filter = option
                    }
                }
            }
        }
    }

    private var doneToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                showDone.toggle()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: showDone ? "eye.slash" : "eye")
                    .font(.system(size: 8, weight: .bold))
                Text(showDone ? "Hide done" : "Show done")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(showDone ? "Hide completed tasks" : "Show completed tasks")
    }

    /// Board-only option for splitting each status column by date, by project,
    /// or by date and then project. The interval only applies to date grouping.
    private var groupMenu: some View {
        Menu {
            Picker("Group by", selection: groupingBinding) {
                ForEach(TaskGrouping.allCases) { option in
                    Text(option.title).tag(option)
                }
            }

            Picker("Date interval", selection: dateIntervalBinding) {
                ForEach(TaskDateInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 8, weight: .bold))
                Text(groupMenuLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    grouping == .none ? Color.primary.opacity(0.06) : Theme.accent.opacity(0.14)
                )
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(grouping == .none ? Color.secondary : Theme.accent)
        .help("Group the board or list by date, project, or both")
        .accessibilityLabel("Grouping: \(grouping.title)")
    }

    private var groupMenuLabel: String {
        switch grouping {
        case .none:
            return "Group"
        case .project:
            return "By project"
        case .date:
            return "By \(dateInterval.title.lowercased())"
        case .dateAndProject:
            return "By \(dateInterval.title.lowercased()) + project"
        }
    }

    private var newTaskButton: some View {
        Button {
            showingNewSession = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .bold))
                Text("New task")
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Theme.accent.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
        .help("Start a session and add it to the task board")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.tasks.isEmpty {
            ScrollView {
                emptyContent
            }
        } else if filteredTasks.isEmpty {
            ScrollView {
                EmptyState(
                    icon: "line.3.horizontal.decrease.circle",
                    title: "No matching tasks",
                    subtitle: "Try another project, date range, or status."
                )
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        } else if usesBoard {
            board
        } else {
            filteredList
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        Group {
            if state.isInitialLoading || state.tasksFetchedAt == nil {
                SessionListSkeleton(count: 3)
                    .shimmering()
            } else {
                EmptyState(
                    icon: "checklist",
                    title: "No tasks yet",
                    subtitle: "New sessions become tasks. Finished work lands here for review."
                )
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var filteredList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if filter == .all {
                    let sessions = taskSessions(for: .all)
                    if sessions.isEmpty {
                        EmptyState(
                            icon: "checklist",
                            title: "No tasks",
                            subtitle: "Show done tasks to see completed work."
                        )
                        .frame(maxWidth: 560, alignment: .leading)
                    } else if grouping != .none {
                        groupedList(sessions)
                    } else {
                        ForEach(visibleSections, id: \.self) { status in
                            let sessions = filteredTasks.filter { $0.taskStatus == status }
                            if !sessions.isEmpty {
                                section(status: status, sessions: sessions)
                            }
                        }
                    }
                } else {
                    let sessions = taskSessions(for: filter)
                    if sessions.isEmpty {
                        EmptyState(
                            icon: filter.icon,
                            title: emptyTitle,
                            subtitle: emptySubtitle
                        )
                        .frame(maxWidth: 560, alignment: .leading)
                    } else if grouping != .none {
                        groupedList(sessions)
                    } else {
                        section(status: status(for: filter) ?? .review, sessions: sessions)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The narrow panel has no board columns, so the grouping menu also
    /// applies to its list. Date grouping keeps the newest buckets first.
    @ViewBuilder
    private func groupedList(_ sessions: [Session]) -> some View {
        switch grouping {
        case .none:
            EmptyView()
        case .project:
            ForEach(projectGroups(for: sessions)) { group in
                projectSection(group, compact: false)
            }
        case .date:
            ForEach(dateGroups(for: sessions)) { group in
                dateSection(group, showsProjects: false, compact: false)
            }
        case .dateAndProject:
            ForEach(dateGroups(for: sessions)) { group in
                dateSection(group, showsProjects: true, compact: false)
            }
        }
    }

    // MARK: - Wide board

    @ViewBuilder
    private var board: some View {
        let columns = CGFloat(boardOrder.count)
        let fitted = (availableWidth - columnSpacing * (columns - 1)) / columns

        if fitted >= columnMinWidth {
            // The window is wide enough for every column, so share the width
            // between them. This is the common case on a large display.
            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(boardOrder, id: \.self) { status in
                    boardColumn(status: status)
                }
            }
        } else {
            // Showing Done adds a column that does not fit yet. Keep the cards
            // readable and let the board scroll sideways until the window grows.
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: columnSpacing) {
                    ForEach(boardOrder, id: \.self) { status in
                        boardColumn(status: status)
                            .frame(width: columnMinWidth)
                    }
                }
                .padding(.bottom, 2)
            }
        }
    }

    private func boardColumn(status: SessionTask.Status) -> some View {
        let sessions = filteredTasks.filter { $0.taskStatus == status }
        let ids = sessions.map(\.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(taskStatusTint(status))
                Text(status.title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(sessions.count)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(
                        sessions.isEmpty ? Color.secondary.opacity(0.55) : taskStatusTint(status)
                    )
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: grouping == .none ? 8 : 10) {
                    if sessions.isEmpty {
                        emptyBoardColumn(status)
                    } else {
                        switch grouping {
                        case .none:
                            ForEach(sessions) { session in
                                TaskCard(session: session, compact: true)
                                    .transition(.recentInsertion)
                            }
                        case .project:
                            ForEach(projectGroups(for: sessions)) { group in
                                projectSection(group)
                            }
                        case .date:
                            ForEach(dateGroups(for: sessions)) { group in
                                dateSection(group, showsProjects: false)
                            }
                        case .dateAndProject:
                            ForEach(dateGroups(for: sessions)) { group in
                                dateSection(group, showsProjects: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 2)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .animateRecentInsertion(ids: ids)
    }

    /// Board projects ordered by their most recent activity. Every column uses
    /// the same order, so a project stays in the same place as the eye moves
    /// between statuses.
    private var projectOrder: [String] {
        var latest: [String: Date] = [:]
        for session in filteredTasks {
            guard let status = session.taskStatus, boardOrder.contains(status) else { continue }
            let updated = session.time.updatedDate
            if let existing = latest[session.projectID], existing >= updated { continue }
            latest[session.projectID] = updated
        }
        return latest.sorted { $0.value > $1.value }.map(\.key)
    }

    private func projectGroups(for sessions: [Session]) -> [ProjectTaskGroup] {
        let buckets = Dictionary(grouping: sessions, by: \.projectID)
        let ordered = projectOrder.filter { buckets[$0] != nil }
        let rest = buckets.keys.filter { !ordered.contains($0) }.sorted()
        return (ordered + rest).compactMap { key in
            guard let group = buckets[key], let first = group.first else { return nil }
            return ProjectTaskGroup(
                id: key,
                name: state.projectName(for: first),
                sessions: group
            )
        }
    }

    private func projectSection(_ group: ProjectTaskGroup, compact: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                Text(group.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(group.sessions.count)")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)

            ForEach(group.sessions) { session in
                TaskCard(session: session, compact: compact, showsProject: false)
                    .transition(.recentInsertion)
            }
        }
    }

    /// Buckets one column's sessions into the chosen date interval, newest
    /// bucket first. The sessions inside a bucket keep the board's activity
    /// order.
    private func dateGroups(for sessions: [Session]) -> [DateTaskGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [Session]] = [:]
        for session in sessions {
            let start = dateBucketStart(for: groupingDate(for: session), calendar: calendar)
            buckets[start, default: []].append(session)
        }
        return buckets.keys.sorted(by: >).map { start in
            DateTaskGroup(
                id: start,
                title: dateGroupTitle(for: start, calendar: calendar),
                sessions: buckets[start] ?? []
            )
        }
    }

    /// Done tasks are filed under the day they were accepted; everything else
    /// uses the last activity the board already shows.
    private func groupingDate(for session: Session) -> Date {
        if session.taskStatus == .done, let done = session.task?.doneDate {
            return done
        }
        return session.time.updatedDate
    }

    private func dateBucketStart(for date: Date, calendar: Calendar) -> Date {
        switch dateInterval {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start
                ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }
    }

    private func dateGroupTitle(for start: Date, calendar: Calendar) -> String {
        let now = Date()
        switch dateInterval {
        case .day:
            if calendar.isDateInToday(start) { return "Today" }
            if calendar.isDateInYesterday(start) { return "Yesterday" }
            return Self.dayGroupFormatter.string(from: start)
        case .week:
            if calendar.isDate(start, equalTo: now, toGranularity: .weekOfYear) {
                return "This week"
            }
            if let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
               calendar.isDate(start, equalTo: previous, toGranularity: .weekOfYear) {
                return "Last week"
            }
            return "Week of \(Self.weekGroupFormatter.string(from: start))"
        case .month:
            if calendar.isDate(start, equalTo: now, toGranularity: .month) {
                return "This month"
            }
            if let previous = calendar.date(byAdding: .month, value: -1, to: now),
               calendar.isDate(start, equalTo: previous, toGranularity: .month) {
                return "Last month"
            }
            return Self.monthGroupFormatter.string(from: start)
        }
    }

    private func dateSection(
        _ group: DateTaskGroup,
        showsProjects: Bool,
        compact: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                Text(group.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(group.sessions.count)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)

            if showsProjects {
                ForEach(projectGroups(for: group.sessions)) { project in
                    projectSection(project, compact: compact)
                }
            } else {
                ForEach(group.sessions) { session in
                    TaskCard(session: session, compact: compact)
                        .transition(.recentInsertion)
                }
            }
        }
    }

    private static let dayGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    private static let weekGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let monthGroupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private func emptyBoardColumn(_ status: SessionTask.Status) -> some View {
        VStack(spacing: 5) {
            Image(systemName: status.icon)
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No tasks")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
    }

    private func section(status: SessionTask.Status, sessions: [Session]) -> some View {
        let ids = sessions.map(\.id)
        return LazyVStack(alignment: .leading, spacing: 8) {
            SectionHeader(status.title) {
                Text("\(sessions.count)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(
                        status == .review ? Theme.warn
                            : status == .queued ? Theme.reasoning
                            : .secondary
                    )
            }

            ForEach(sessions) { session in
                TaskCard(session: session)
                    .transition(.recentInsertion)
            }
        }
        .animateRecentInsertion(ids: ids)
    }

    private func taskSessions(for filter: TaskBoardFilter) -> [Session] {
        let matched: [Session]
        switch filter {
        case .all:
            matched = filteredTasks
        case .queued:
            matched = filteredTasks.filter { $0.taskStatus == .queued }
        case .review:
            matched = filteredTasks.filter { $0.taskStatus == .review }
        case .working:
            matched = filteredTasks.filter { $0.taskStatus == .working }
        case .done:
            matched = filteredTasks.filter { $0.taskStatus == .done }
        }
        return showDone ? matched : matched.filter { $0.taskStatus != .done }
    }

    private func count(for filter: TaskBoardFilter) -> Int {
        taskSessions(for: filter).count
    }

    private func status(for filter: TaskBoardFilter) -> SessionTask.Status? {
        switch filter {
        case .queued: return .queued
        case .review: return .review
        case .working: return .working
        case .done: return .done
        case .all: return nil
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .queued: return "Nothing queued"
        case .review: return "Nothing to review"
        case .working: return "Nothing running"
        case .done: return "No completed tasks"
        case .all: return "No tasks"
        }
    }

    private var emptySubtitle: String {
        switch filter {
        case .queued: return "Tasks scheduled for later, or waiting for a free agent slot."
        case .review: return "Finished sessions wait here until you accept them."
        case .working: return "Start a task and its progress shows up here."
        case .done: return "Accepted tasks are kept here for reference."
        case .all: return "New sessions become tasks automatically."
        }
    }
}

private struct TaskCard: View {
    @EnvironmentObject private var state: AppState
    let session: Session
    /// Narrower card used in the wide board's columns. The column header
    /// already carries the status, so the card drops its status icon and moves
    /// the failure badge under the metadata to keep the title readable.
    var compact = false
    /// Off when the column is grouped by project and the section header
    /// already names the project.
    var showsProject = true

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 6 : 9) {
            if !compact {
                statusIcon
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(compact ? 3 : 2)
                    if !compact {
                        Spacer(minLength: 4)
                        failureBadge
                    }
                }

                HStack(spacing: 6) {
                    if showsProject {
                        Text(state.projectName(for: session))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("·")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Text(relativeTime)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                if compact {
                    failureBadge
                }

                if let labels = session.task?.labels, !labels.isEmpty {
                    let visible = compact ? Array(labels.prefix(2)) : labels
                    HStack(spacing: 4) {
                        ForEach(visible) { label in
                            Chip(
                                text: label.title,
                                systemImage: label.systemImage,
                                tint: tint(for: label)
                            )
                        }
                        if compact, labels.count > visible.count {
                            Chip(text: "+\(labels.count - visible.count)", tint: .secondary)
                        }
                    }
                }
            }

            actions
        }
        .card(padding: compact ? 9 : 10)
        .contentShape(Rectangle())
        .onTapGesture { state.open(session) }
        .help("Open the conversation")
    }

    @ViewBuilder
    private var failureBadge: some View {
        if session.hasFailureOutcome {
            Chip(
                text: session.outcomeLabel,
                systemImage: "exclamationmark.triangle.fill",
                tint: Theme.danger
            )
            .fixedSize()
        }
    }

    private var statusIcon: some View {
        Image(systemName: session.taskStatus?.icon ?? "circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(statusTint)
            .frame(width: 18, height: 18)
            .background(Circle().fill(statusTint.opacity(0.12)))
            .padding(.top, 1)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 4) {
            switch session.taskStatus {
            case .queued?:
                iconButton("play.fill", help: "Start now", tint: Theme.running) {
                    Task { await state.startQueuedTask(session) }
                }
            case .review?:
                iconButton("checkmark", help: "Mark done", tint: Theme.accent) {
                    Task { await state.markTaskDone(session) }
                }
            case .done?:
                iconButton("arrow.uturn.backward", help: "Reopen task", tint: Theme.accent) {
                    Task { await state.reopenTask(session) }
                }
            case .working?:
                iconButton("arrow.up.right.square", help: "Open running task", tint: Theme.running) {
                    state.open(session)
                }
            default:
                iconButton("arrow.uturn.backward", help: "Reopen task", tint: Color.secondary) {
                    Task { await state.reopenTask(session) }
                }
            }

            Menu {
                Button("Open conversation") { state.open(session) }
                if session.taskStatus == .queued {
                    Button("Start now") { Task { await state.startQueuedTask(session) } }
                    Button("Remove from queue", role: .destructive) {
                        Task { await state.cancelQueuedTask(session) }
                    }
                } else if session.taskStatus == .done {
                    Button("Reopen") { Task { await state.reopenTask(session) } }
                } else if session.taskStatus == .dismissed {
                    Button("Reopen") { Task { await state.reopenTask(session) } }
                } else {
                    Button("Mark done") { Task { await state.markTaskDone(session) } }
                    Button("Dismiss", role: .destructive) {
                        Task { await state.dismissTask(session) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More task actions")
        }
    }

    private func iconButton(
        _ icon: String,
        help: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(tint.opacity(0.12)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private var relativeTime: String {
        if session.taskStatus == .done, let done = session.task?.doneDate {
            return "Done \(Fmt.relative(from: done))"
        }
        if session.taskStatus == .queued {
            if let until = session.task?.queuedUntilDate, until > Date() {
                return "Starts \(Fmt.relative(from: until))"
            }
            return "Waiting for a slot"
        }
        return Fmt.relative(from: session.time.updatedDate)
    }

    private var statusTint: Color {
        taskStatusTint(session.taskStatus)
    }

    private func tint(for label: TaskLabel) -> Color {
        switch label.id {
        case "bug", "security", "security-sensitive", "data-loss":
            return Theme.danger
        case "breaking-change":
            return Theme.warn
        case "feature", "product":
            return Theme.accent
        case "performance":
            return Theme.cacheRead
        case "tests", "technical":
            return Theme.running
        case "refactor", "question":
            return Theme.reasoning
        default:
            return .secondary
        }
    }
}

/// Shared status colour for task rows and the wide board's column headers.
private func taskStatusTint(_ status: SessionTask.Status?) -> Color {
    switch status {
    case .queued: return Theme.reasoning
    case .review: return Theme.warn
    case .working: return Theme.running
    case .done: return Theme.accent
    case .dismissed: return .secondary
    case nil: return .secondary
    }
}
