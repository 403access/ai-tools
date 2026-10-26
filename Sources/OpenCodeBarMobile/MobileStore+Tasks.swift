import Combine
import Foundation

extension MobileStore {
    // MARK: - Task board

    /// Loads the board from the hub. The endpoint only returns tracked
    /// top-level sessions, so it is cheap enough to refresh with the feed.
    func refreshTasks(force: Bool = false) async {
        guard let api else { return }
        if isRefreshingTasks { return }
        if !force, let fetched = tasksFetchedAt,
           Date().timeIntervalSince(fetched) < 3 {
            return
        }
        isRefreshingTasks = true
        defer { isRefreshingTasks = false }

        do {
            let fetched = try await api.tasks(limit: 1_000)
            tasks = sortedTasks(fetched)
            tasksFetchedAt = Date()
            tasksError = nil
        } catch {
            // Keep the last board; a later refresh usually recovers.
            if tasks.isEmpty {
                tasksError = message(for: error)
            }
        }
    }

    var reviewTasks: [Session] {
        tasks.filter { $0.taskStatus == .review }
    }

    var workingTasks: [Session] {
        tasks.filter { $0.taskStatus == .working }
    }

    var doneTasks: [Session] {
        tasks.filter { $0.taskStatus == .done }
    }

    var reviewTaskCount: Int { reviewTasks.count }

    func tasks(matching filter: TaskBoardFilter) -> [Session] {
        switch filter {
        case .all:
            return tasks
        case .review:
            return reviewTasks
        case .working:
            return workingTasks
        case .done:
            return doneTasks
        }
    }

    func markTaskDone(_ session: Session) async {
        await setTaskStatus(session, status: .done)
    }

    func reopenTask(_ session: Session) async {
        await setTaskStatus(session, status: .review)
    }

    func dismissTask(_ session: Session) async {
        await setTaskStatus(session, status: .dismissed)
    }

    /// Updates the board immediately so it responds without waiting for the
    /// round-trip, then reconciles with the hub's derived status. A failure
    /// puts the previous row back.
    func setTaskStatus(_ session: Session, status: SessionTask.Status) async {
        guard let api else {
            tasksError = "Not connected to the hub"
            return
        }

        let previous = session
        var optimistic = session
        if optimistic.task == nil {
            optimistic.task = SessionTask(
                status: status,
                labels: [],
                createdAt: Date().timeIntervalSince1970 * 1_000
            )
        }
        optimistic.task?.status = status
        if status == .done || status == .dismissed {
            optimistic.task?.doneAt = Date().timeIntervalSince1970 * 1_000
        } else {
            optimistic.task?.doneAt = nil
        }
        storeTaskSession(optimistic)

        let wireStatus: String
        switch status {
        case .done: wireStatus = "done"
        case .dismissed: wireStatus = "dismissed"
        case .working, .review: wireStatus = "open"
        }

        do {
            let updated = try await api.updateTask(id: session.id, status: wireStatus)
            storeTaskSession(updated)
            tasksError = nil
        } catch {
            storeTaskSession(previous)
            tasksError = message(for: error)
        }
    }

    /// Called after a prompt is accepted so a reviewed task immediately shows
    /// as working instead of waiting for the next board refresh.
    func noteTaskPrompt(id: String) {
        guard let session = taskSession(id: id) else { return }
        var updated = session
        updated.task?.status = .working
        updated.task?.doneAt = nil
        storeTaskSession(updated)
    }

    private func taskSession(id: String) -> Session? {
        tasks.first { $0.id == id } ?? session(id: id)
    }

    /// Merges session rows that changed during sync into the board. The sync
    /// feed carries task metadata too, so labels and derived status stay fresh
    /// without refetching the whole board.
    func mergeTaskUpdates(_ updates: [Session]) {
        guard !tasks.isEmpty else { return }
        var byID = Dictionary(
            tasks.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var changed = false
        for update in updates where update.task != nil {
            if let current = byID[update.id], current != update {
                byID[update.id] = update
                changed = true
            }
        }
        if changed { tasks = sortedTasks(Array(byID.values)) }
    }

    func sortedTasks(_ sessions: [Session]) -> [Session] {
        sessions.sorted { lhs, rhs in
            let left = lhs.taskStatus ?? .review
            let right = rhs.taskStatus ?? .review
            if rank(left) != rank(right) { return rank(left) < rank(right) }
            let leftDate = left == .done ? (lhs.task?.doneDate ?? lhs.time.updatedDate) : lhs.time.updatedDate
            let rightDate = right == .done ? (rhs.task?.doneDate ?? rhs.time.updatedDate) : rhs.time.updatedDate
            if leftDate != rightDate { return leftDate > rightDate }
            return lhs.id < rhs.id
        }
    }

    private func rank(_ status: SessionTask.Status) -> Int {
        switch status {
        case .review: return 0
        case .working: return 1
        case .done: return 2
        case .dismissed: return 3
        }
    }

    /// Keeps every list that can show this session in step. The board, the live
    /// feeds, and the cache hold separate copies of the same value type.
    private func storeTaskSession(_ session: Session) {
        if let index = tasks.firstIndex(where: { $0.id == session.id }) {
            tasks[index] = session
        } else if session.task != nil {
            tasks.insert(session, at: 0)
        }
        tasks = sortedTasks(tasks)

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        }
        database?.upsertSessions([session])
        rebuildDerived()
    }
}
