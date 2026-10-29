import SwiftUI
import UIKit

/// Grouping choices for the task list and kanban. Date grouping can stand
/// alone or be combined with projects, in which case date comes first.
enum MobileTaskGrouping: String, CaseIterable, Identifiable, Hashable {
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

    /// Whether the grouping buckets by date, and so needs an interval.
    var usesDate: Bool {
        self == .date || self == .dateAndProject
    }
}

/// Bucket size for date grouping.
enum MobileTaskDateInterval: String, CaseIterable, Identifiable, Hashable {
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

/// Project-management board for sessions. New top-level sessions become tasks,
/// running ones are in progress, and finished ones wait in review until the
/// user accepts them or sends another prompt. Rotating a phone to landscape
/// swaps the scrolling list for a three-column kanban so every status stays in
/// view at once.
struct TasksView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject var store: MobileStore
    @EnvironmentObject private var router: MobileRouter
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var path = NavigationPath()
    @State private var filter: TaskBoardFilter = .review
    @State private var showingNewSession = false
    @State private var sessionToOpen: Session?
    @State var selectedProjectID: String?
    @State var timeFilter: SessionTimeFilter = .all
    @State var statusFilter: SessionStatusFilter = .all
    /// How the list and kanban split tasks. Mirrors the macOS board: date
    /// grouping can stand alone or be combined with projects. Date and project
    /// is the default.
    @AppStorage("tasks.grouping") var groupingRaw = "dateAndProject"
    /// Bucket size for date grouping.
    @AppStorage("tasks.dateInterval") var dateIntervalRaw = "day"
    @State private var showingFilters = false
    @State private var deepLinkAttempt = ""
    /// Done tasks are reference only, so they stay out of the board (and its
    /// landscape columns) until the user asks for them.
    @AppStorage("tasks.showDone") private var showDone = false

    private let sectionOrder: [SessionTask.Status] = [
        .queued, .review, .working, .done, .dismissed,
    ]

    private var visibleSections: [SessionTask.Status] {
        sectionOrder.filter { showDone || $0 != .done }
    }

    /// Dismissed tasks stay out of the kanban. The board is for work that is
    /// still on the user's plate; dismissed rows remain available in portrait's
    /// All filter.
    private var kanbanOrder: [SessionTask.Status] {
        [.queued, .review, .working] + (showDone ? [.done] : [])
    }

    private var isLandscape: Bool { verticalSizeClass == .compact }

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
                } else if isLandscape {
                    kanban
                } else {
                    content
                }
            }
            .mobileScreenBackground()
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: activeFilterCount > 0
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Task filters")
                    .accessibilityValue(
                        activeFilterCount > 0
                            ? "\(activeFilterCount) active"
                            : "None active"
                    )
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        ConnectionPill(connection: connection, activeCount: activeCount)
                        Button {
                            showingNewSession = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New task")
                    }
                }
            }
            .navigationDestination(for: Session.self) { session in
                SessionDetailView(
                    sessionID: session.id,
                    fallback: session,
                    onOpenSession: { path.append($0) }
                )
            }
            .refreshable { await store.refreshAll() }
            .task { await store.refreshTasks() }
            .task(id: store.lastUpdated) { openRequestedSession() }
            .onChange(of: router.requestedSessionID) { _, _ in openRequestedSession() }
            .onAppear {
                openRequestedSession()
                applyDefaultGroupingIfNeeded()
            }
            .onChange(of: showDone) { _, visible in
                if !visible, filter == .done { filter = .review }
            }
            .sheet(isPresented: $showingNewSession, onDismiss: openCreatedSession) {
                MobileNewSessionSheet { session in
                    sessionToOpen = session
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showingFilters) {
                MobileTaskFiltersSheet(
                    selectedProjectID: $selectedProjectID,
                    timeFilter: $timeFilter,
                    statusFilter: $statusFilter,
                    grouping: groupingBinding,
                    dateInterval: dateIntervalBinding,
                    projects: filterProjects
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                filters()

                if let error = store.tasksError, store.tasks.isEmpty {
                    NoticeRow(icon: "exclamationmark.triangle", message: error, tint: Theme.warn)
                }

                if store.tasks.isEmpty {
                    if store.tasksFetchedAt == nil {
                        SessionListSkeleton(count: 3, showsActivity: true)
                            .shimmering()
                    } else {
                        EmptyState(
                            icon: "checklist",
                            title: "No tasks yet",
                            subtitle: "New sessions become tasks. Finished work lands here for review."
                        )
                    }
                } else if filteredTasks.isEmpty {
                    EmptyState(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "No matching tasks",
                        subtitle: "Try another project, date range, or status."
                    )
                } else if filter == .all {
                    let sessions = taskSessions(for: .all)
                    if sessions.isEmpty {
                        EmptyState(
                            icon: "checklist",
                            title: "No tasks",
                            subtitle: "Show done tasks to see completed work."
                        )
                    } else {
                        taskList(sessions, status: nil)
                    }
                } else {
                    let sessions = taskSessions(for: filter)
                    if sessions.isEmpty {
                        EmptyState(
                            icon: filter.icon,
                            title: emptyTitle,
                            subtitle: emptySubtitle
                        )
                    } else {
                        taskList(sessions, status: status(for: filter) ?? .review)
                    }
                }

                if let updated = store.tasksFetchedAt {
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

    // MARK: - Landscape kanban

    private var kanban: some View {
        VStack(spacing: 0) {
            filters()
                .padding(.horizontal, 16)
                .padding(.top, 8)

            Group {
                if let error = store.tasksError, store.tasks.isEmpty {
                    VStack(spacing: 0) {
                        NoticeRow(icon: "exclamationmark.triangle", message: error, tint: Theme.warn)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                } else if store.tasks.isEmpty {
                    if store.tasksFetchedAt == nil {
                        ScrollView {
                            SessionListSkeleton(count: 3, showsActivity: true)
                                .shimmering()
                                .padding(16)
                        }
                    } else {
                        VStack(spacing: 0) {
                            EmptyState(
                                icon: "checklist",
                                title: "No tasks yet",
                                subtitle: "New sessions become tasks. Finished work lands here for review."
                            )
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                    }
                } else if filteredTasks.isEmpty {
                    VStack(spacing: 0) {
                        EmptyState(
                            icon: "line.3.horizontal.decrease.circle",
                            title: "No matching tasks",
                            subtitle: "Try another project, date range, or status."
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                } else {
                    board
                }
            }
        }
    }

    private var board: some View {
        GeometryReader { proxy in
            let columnWidth = kanbanColumnWidth(available: proxy.size.width)
            let columnHeight = max(140, proxy.size.height - 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(kanbanOrder, id: \.self) { status in
                        kanbanColumn(
                            status: status,
                            width: columnWidth,
                            height: columnHeight
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func kanbanColumnWidth(available: CGFloat) -> CGFloat {
        let spacing: CGFloat = 12
        let horizontalPadding: CGFloat = 16
        // Aim to show every visible status side by side. Showing Done adds a
        // fourth column, and very narrow phones (or large text) fall back to
        // horizontal scrolling.
        let columns = CGFloat(max(kanbanOrder.count, 1))
        let fitted = (available - horizontalPadding * 2 - spacing * (columns - 1)) / columns
        return min(max(fitted, 220), 340)
    }

    private func kanbanColumn(
        status: SessionTask.Status,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        let sessions = filteredTasks.filter { $0.taskStatus == status }
        let ids = sessions.map(\.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint(for: status))
                Text(status.title.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(sessions.count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(
                        status == .review && !sessions.isEmpty ? Theme.warn
                            : status == .queued && !sessions.isEmpty ? Theme.reasoning
                            : .secondary
                    )
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 2)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: grouping == .none ? 8 : 10) {
                    if sessions.isEmpty {
                        emptyColumn(status)
                    } else {
                        kanbanCards(sessions)
                    }
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(8)
        .frame(width: width, height: height, alignment: .top)
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

    private func emptyColumn(_ status: SessionTask.Status) -> some View {
        VStack(spacing: 6) {
            Image(systemName: status.icon)
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No tasks")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
        )
    }

    private func tint(for status: SessionTask.Status) -> Color {
        switch status {
        case .queued: return Theme.reasoning
        case .review: return Theme.warn
        case .working: return Theme.running
        case .done: return Theme.accent
        case .dismissed: return .secondary
        }
    }

    private func filters() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskBoardFilter.allCases) { option in
                    if option != .done || showDone {
                        ChoiceChip(
                            title: "\(option.shortTitle) \(count(for: option))",
                            isSelected: filter == option,
                            fontSize: 11
                        ) {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                filter = option
                            }
                        }
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showDone.toggle()
                    }
                } label: {
                    Image(systemName: showDone ? "eye.slash" : "eye")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 24)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showDone ? "Hide done tasks" : "Show done tasks")
            }
            .padding(.vertical, 1)
        }
    }

    private func section(status: SessionTask.Status, sessions: [Session]) -> some View {
        let ids = sessions.map(\.id)
        return LazyVStack(alignment: .leading, spacing: 8) {
            SectionHeader(status.title) {
                Text("\(sessions.count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(
                        status == .review ? Theme.warn
                            : status == .queued ? Theme.reasoning
                            : Color.secondary
                    )
            }

            ForEach(sessions) { session in
                MobileTaskCard(
                    session: session,
                    project: store.projectName(for: session),
                    onOpen: { path.append(session) }
                )
                .transition(.recentInsertion)
            }
        }
        .animateRecentInsertion(ids: ids)
    }

    /// Applies the chosen grouping to a set of sessions. Without grouping the
    /// list keeps its status sections; grouped modes replace them with project
    /// or date sections instead.
    @ViewBuilder
    private func taskList(_ sessions: [Session], status: SessionTask.Status?) -> some View {
        if grouping == .none {
            if let status {
                section(status: status, sessions: sessions)
            } else {
                ForEach(visibleSections, id: \.self) { status in
                    let matches = sessions.filter { $0.taskStatus == status }
                    if !matches.isEmpty {
                        section(status: status, sessions: matches)
                    }
                }
            }
        } else {
            groupedSections(sessions)
        }
    }

    @ViewBuilder
    private func groupedSections(_ sessions: [Session]) -> some View {
        switch grouping {
        case .none:
            EmptyView()
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

    /// The kanban shows the same grouping inside each status column.
    @ViewBuilder
    private func kanbanCards(_ sessions: [Session]) -> some View {
        switch grouping {
        case .none:
            ForEach(sessions) { session in
                MobileTaskCard(
                    session: session,
                    project: store.projectName(for: session),
                    compact: true,
                    onOpen: { path.append(session) }
                )
                .transition(.recentInsertion)
            }
        case .project:
            ForEach(projectGroups(for: sessions)) { group in
                projectSection(group, compact: true)
            }
        case .date:
            ForEach(dateGroups(for: sessions)) { group in
                dateSection(group, showsProjects: false, compact: true)
            }
        case .dateAndProject:
            ForEach(dateGroups(for: sessions)) { group in
                dateSection(group, showsProjects: true, compact: true)
            }
        }
    }

    /// Projects ordered by their most recent activity, so a project keeps the
    /// same position across status columns.
    private var projectOrder: [String] {
        var latest: [String: Date] = [:]
        for session in filteredTasks {
            let updated = session.time.updatedDate
            if let existing = latest[session.projectID], existing >= updated { continue }
            latest[session.projectID] = updated
        }
        return latest.sorted { $0.value > $1.value }.map(\.key)
    }

    private func projectGroups(for sessions: [Session]) -> [MobileProjectTaskGroup] {
        let buckets = Dictionary(grouping: sessions, by: \.projectID)
        let ordered = projectOrder.filter { buckets[$0] != nil }
        let rest = buckets.keys.filter { !ordered.contains($0) }.sorted()
        return (ordered + rest).compactMap { key in
            guard let group = buckets[key], let first = group.first else { return nil }
            return MobileProjectTaskGroup(
                id: key,
                name: store.projectName(for: first),
                sessions: group
            )
        }
    }

    private func projectSection(
        _ group: MobileProjectTaskGroup,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                Text(group.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(group.sessions.count)")
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)

            ForEach(group.sessions) { session in
                MobileTaskCard(
                    session: session,
                    project: store.projectName(for: session),
                    compact: compact,
                    showsProject: false,
                    onOpen: { path.append(session) }
                )
                .transition(.recentInsertion)
            }
        }
    }

    /// Buckets sessions into the chosen date interval, newest bucket first.
    private func dateGroups(for sessions: [Session]) -> [MobileDateTaskGroup] {
        let calendar = Calendar.current
        var buckets: [Date: [Session]] = [:]
        for session in sessions {
            let start = dateBucketStart(for: groupingDate(for: session), calendar: calendar)
            buckets[start, default: []].append(session)
        }
        return buckets.keys.sorted(by: >).map { start in
            MobileDateTaskGroup(
                id: start,
                title: dateGroupTitle(for: start, calendar: calendar),
                sessions: buckets[start] ?? []
            )
        }
    }

    /// Done tasks are filed under the day they were accepted; everything else
    /// uses the last activity the list already shows.
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
        _ group: MobileDateTaskGroup,
        showsProjects: Bool,
        compact: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent.opacity(0.85))
                Text(group.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(group.sessions.count)")
                    .font(.caption2.weight(.bold))
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
                    MobileTaskCard(
                        session: session,
                        project: store.projectName(for: session),
                        compact: compact,
                        onOpen: { path.append(session) }
                    )
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

private struct MobileProjectTaskGroup: Identifiable {
    let id: String
    let name: String
    let sessions: [Session]
}

private struct MobileDateTaskGroup: Identifiable {
    /// Start of the bucket, so a group keeps its identity while cards update.
    let id: Date
    let title: String
    let sessions: [Session]
}

private struct MobileTaskCard: View {
    @EnvironmentObject private var store: MobileStore
    let session: Session
    let project: String
    /// Narrower card used inside the landscape kanban columns. The column
    /// header already carries the status, so the card drops its icon and status
    /// line to keep the title, metadata, and action from wrapping.
    var compact = false
    /// Off when a project section header already names the project.
    var showsProject = true
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: compact ? 6 : 10) {
                if !compact {
                    statusIcon
                }
                details
                Spacer(minLength: 4)
                menu
            }

            HStack(spacing: 8) {
                if !compact {
                    Text(session.taskStatus?.title ?? "Task")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusTint)
                }
                Spacer(minLength: 4)
                primaryAction
            }
        }
        .card(padding: compact ? 10 : 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAction(named: Text("Open conversation"), onOpen)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(session.displayTitle)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)

            HStack(spacing: 5) {
                if showsProject {
                    Text(project)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !compact, session.hasFailureOutcome {
                    failureChip
                }
            }

            // Narrow kanban cards put the failure badge on its own line so the
            // project and relative time keep a full line.
            if compact, session.hasFailureOutcome {
                failureChip
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
    }

    private var statusIcon: some View {
        Image(systemName: session.taskStatus?.icon ?? "circle")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(statusTint)
            .frame(width: 26, height: 26)
            .background(Circle().fill(statusTint.opacity(0.13)))
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch session.taskStatus {
        case .queued?:
            actionButton("Start now", icon: "play.fill", tint: Theme.running) {
                Task { await store.startQueuedTask(session) }
            }
        case .review?:
            actionButton("Mark done", icon: "checkmark", tint: Theme.accent) {
                Task { await store.markTaskDone(session) }
            }
        case .working?:
            actionButton("Open", icon: "arrow.up.right.square", tint: Theme.running) {
                onOpen()
            }
        case .done?, .dismissed?:
            actionButton("Reopen", icon: "arrow.uturn.backward", tint: Theme.accent) {
                Task { await store.reopenTask(session) }
            }
        default:
            EmptyView()
        }
    }

    private var menu: some View {
        Menu {
            Button("Open conversation", systemImage: "bubble.left.and.bubble.right") {
                onOpen()
            }
            if session.taskStatus == .queued {
                Button("Start now", systemImage: "play.fill") {
                    Task { await store.startQueuedTask(session) }
                }
                Button(role: .destructive) {
                    Task { await store.cancelQueuedTask(session) }
                } label: {
                    Label("Remove from queue", systemImage: "xmark.circle")
                }
            } else if session.taskStatus == .done || session.taskStatus == .dismissed {
                Button("Reopen", systemImage: "arrow.uturn.backward") {
                    Task { await store.reopenTask(session) }
                }
            } else {
                Button("Mark done", systemImage: "checkmark") {
                    Task { await store.markTaskDone(session) }
                }
                Button(role: .destructive) {
                    Task { await store.dismissTask(session) }
                } label: {
                    Label("Dismiss", systemImage: "eye.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More task actions")
    }

    private func actionButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(tint.opacity(0.14)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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

    private var failureChip: some View {
        Chip(
            text: session.outcomeLabel,
            systemImage: "exclamationmark.triangle.fill",
            tint: Theme.danger
        )
        .fixedSize()
    }

    private var statusTint: Color {
        switch session.taskStatus {
        case .queued: return Theme.reasoning
        case .review: return Theme.warn
        case .working: return Theme.running
        case .done: return Theme.accent
        case .dismissed: return .secondary
        case nil: return .secondary
        }
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
