import Foundation

extension AppState {
    // MARK: - Task board

    /// Loads the board from the hub. Cheap enough to refresh with the live feed;
    /// the endpoint only returns tracked top-level sessions.
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

    /// Updates a task immediately so the board responds without waiting for the
    /// round-trip, then reconciles with the hub's derived status. A failure puts
    /// the previous row back.
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

    /// Called after a prompt is accepted so a reviewed task immediately shows as
    /// working instead of waiting for the next board refresh.
    func noteTaskPrompt(id: String) {
        guard let session = taskSession(id: id) else { return }
        var updated = session
        updated.task?.status = .working
        updated.task?.doneAt = nil
        storeTaskSession(updated)
    }

    private func taskSession(id: String) -> Session? {
        tasks.first { $0.id == id } ?? sessions.first { $0.id == id }
    }

    private func sortedTasks(_ sessions: [Session]) -> [Session] {
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

    /// Keeps every list that can show this session in step. The board and the
    /// live/history feeds hold separate copies of the same value type.
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
        if let index = history.firstIndex(where: { $0.id == session.id }) {
            history[index] = session
        }
        if selectedSession?.id == session.id {
            selectedSession = session
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
