import SwiftUI

/// Project-management board for sessions. New top-level sessions become tasks,
/// running ones are in progress, and finished ones wait in review until the
/// user accepts them or sends another prompt.
struct TasksTab: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: TaskBoardFilter = .review
    @State private var showingNewSession = false

    private let sectionOrder: [SessionTask.Status] = [.review, .working, .done, .dismissed]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            filters

            if let error = state.tasksError, state.tasks.isEmpty {
                NoticeRow(icon: "exclamationmark.triangle", message: error, tint: Theme.warn)
            }

            if state.tasks.isEmpty {
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
            } else if filter == .all {
                ForEach(sectionOrder, id: \.self) { status in
                    let sessions = state.tasks.filter { $0.taskStatus == status }
                    if !sessions.isEmpty {
                        section(status: status, sessions: sessions)
                    }
                }
            } else {
                let sessions = state.tasks(matching: filter)
                if sessions.isEmpty {
                    EmptyState(
                        icon: filter.icon,
                        title: emptyTitle,
                        subtitle: emptySubtitle
                    )
                } else {
                    section(status: status(for: filter) ?? .review, sessions: sessions)
                }
            }
        }
        .sheet(isPresented: $showingNewSession) {
            NewSessionSheet()
                .environmentObject(state)
        }
        .task { await state.refreshTasks() }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(TaskBoardFilter.allCases) { option in
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

            HStack(spacing: 6) {
                Text("Auto-labelled from the request")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 4)
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
        }
    }

    private func section(status: SessionTask.Status, sessions: [Session]) -> some View {
        let ids = sessions.map(\.id)
        return LazyVStack(alignment: .leading, spacing: 8) {
            SectionHeader(status.title) {
                Text("\(sessions.count)")
                    .font(.system(size: 10, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(status == .review ? Theme.warn : .secondary)
            }

            ForEach(sessions) { session in
                TaskCard(session: session)
                    .transition(.recentInsertion)
            }
        }
        .animateRecentInsertion(ids: ids)
    }

    private func count(for filter: TaskBoardFilter) -> Int {
        state.tasks(matching: filter).count
    }

    private func status(for filter: TaskBoardFilter) -> SessionTask.Status? {
        switch filter {
        case .review: return .review
        case .working: return .working
        case .done: return .done
        case .all: return nil
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .review: return "Nothing to review"
        case .working: return "Nothing running"
        case .done: return "No completed tasks"
        case .all: return "No tasks"
        }
    }

    private var emptySubtitle: String {
        switch filter {
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

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            statusIcon

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(session.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if session.hasFailureOutcome {
                        Chip(
                            text: session.outcomeLabel,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: Theme.danger
                        )
                    }
                }

                HStack(spacing: 6) {
                    Text(state.projectName(for: session))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(relativeTime)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }

                if let labels = session.task?.labels, !labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(labels) { label in
                            Chip(
                                text: label.title,
                                systemImage: label.systemImage,
                                tint: tint(for: label)
                            )
                        }
                    }
                }
            }

            actions
        }
        .card(padding: 10)
        .contentShape(Rectangle())
        .onTapGesture { state.open(session) }
        .help("Open the conversation")
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
                if session.taskStatus == .done {
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
        return Fmt.relative(from: session.time.updatedDate)
    }

    private var statusTint: Color {
        switch session.taskStatus {
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
