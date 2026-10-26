import SwiftUI
import UIKit

/// Project-management board for sessions. New top-level sessions become tasks,
/// running ones are in progress, and finished ones wait in review until the
/// user accepts them or sends another prompt.
struct TasksView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @State private var path = NavigationPath()
    @State private var filter: TaskBoardFilter = .review
    @State private var showingNewSession = false
    @State private var sessionToOpen: Session?

    private let sectionOrder: [SessionTask.Status] = [.review, .working, .done, .dismissed]

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
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                filters

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
                } else if filter == .all {
                    ForEach(sectionOrder, id: \.self) { status in
                        let sessions = store.tasks.filter { $0.taskStatus == status }
                        if !sessions.isEmpty {
                            section(status: status, sessions: sessions)
                        }
                    }
                } else {
                    let sessions = store.tasks(matching: filter)
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

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TaskBoardFilter.allCases) { option in
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
                    .foregroundStyle(status == .review ? Theme.warn : Color.secondary)
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

    private func count(for filter: TaskBoardFilter) -> Int {
        store.tasks(matching: filter).count
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

private struct MobileTaskCard: View {
    @EnvironmentObject private var store: MobileStore
    let session: Session
    let project: String
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                statusIcon
                details
                Spacer(minLength: 4)
                menu
            }

            HStack(spacing: 8) {
                Text(session.taskStatus?.title ?? "Task")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
                Spacer(minLength: 4)
                primaryAction
            }
        }
        .card(padding: 12)
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
                Text(project)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
                Text("·")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if session.hasFailureOutcome {
                    Chip(
                        text: session.outcomeLabel,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: Theme.danger
                    )
                }
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
            if session.taskStatus == .done || session.taskStatus == .dismissed {
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
