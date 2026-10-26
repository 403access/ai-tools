import Foundation

extension AppState {
    // MARK: - Live activity

    func activity(for sessionID: String) -> SessionActivity? {
        liveActivity[sessionID]
    }

    /// Folds an event into the matching session's activity, updates live
    /// cost/tokens, and refreshes the list (debounced) as before.
    func handle(_ event: OpenCodeEvent) {
        if event.type == "server.connected" || event.type == "hub.connected" {
            if eventStreamConnected {
                // Events may have been missed while the stream was down; mark
                // the snapshots stale so the next refresh rebuilds them.
                seedAttempts.removeAll()
                for id in Array(liveActivity.keys) {
                    liveActivity[id]?.updatedAt = .distantPast
                }
            }
            eventStreamConnected = true
        }

        if event.type == "hub.usage" {
            Task { await refreshGoUsage() }
        }

        // Task resolutions and a session going idle both change the board's
        // derived status, so update the review badge even from another tab.
        if event.type == "hub.sessions"
            || event.type == "session.idle"
            || event.type == "session.deleted" {
            if tasksFetchedAt != nil {
                Task { await refreshTasks(force: true) }
            }
        }

        if let id = event.sessionID {
            switch event.type {
            case "session.idle", "session.deleted":
                liveActivity.removeValue(forKey: id)
                activeIDs.remove(id)
                seedAttempts.removeValue(forKey: id)
                rebuildDerived()
            default:
                if event.updatesActivity {
                    var activity = liveActivity[id] ?? SessionActivity(
                        stepStartedAt: sessions.first(where: { $0.id == id })?.time.createdDate ?? Date()
                    )
                    activity.apply(event, directory: sessions.first(where: { $0.id == id })?.directory)
                    liveActivity[id] = activity
                }
                if event.type == "session.usage.updated" {
                    applyUsage(event.data, to: id)
                }
            }
        }

        if event.type == "server.connected"
            || event.type.hasPrefix("hub.")
            || event.type.hasPrefix("session.")
            || event.type.hasPrefix("message.")
            || event.type.hasPrefix("permission.") {
            scheduleLiveRefresh()
        }
    }

    /// Usage events carry fresher totals than the session list, so the row's
    /// cost and token count move while the session runs.
    func applyUsage(_ data: OpenCodeEvent.Payload?, to id: String) {
        guard let data,
              let cost = data.cost,
              let tokens = data.tokens
        else { return }

        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].cost = cost
            sessions[index].tokens = tokens
            updateDerivedSession(sessions[index])
            if selectedSession?.id == id {
                selectedSession = sessions[index]
            }
        }

        for parentID in Array(subagentLists.keys) {
            guard var list = subagentLists[parentID],
                  let index = list.sessions.firstIndex(where: { $0.id == id })
            else { continue }
            list.sessions[index].cost = cost
            list.sessions[index].tokens = tokens
            subagentLists[parentID] = list
        }
    }

    /// Drops activity for sessions that stopped or whose snapshot is old enough
    /// that the poll already reflects the change.
    func pruneActivity() {
        let cutoff = Date().addingTimeInterval(-10)
        let keptActivity = liveActivity.filter { id, activity in
            activeIDs.contains(id) || activity.updatedAt > cutoff
        }
        if keptActivity != liveActivity { liveActivity = keptActivity }
        let keptSeeds = seedAttempts.filter { activeIDs.contains($0.key) }
        if keptSeeds != seedAttempts { seedAttempts = keptSeeds }
    }

    /// Rebuilds activity from the newest messages when the panel starts, when
    /// the event stream reconnects, or when a session has gone quiet for long
    /// enough that a missed event is plausible.
    func seedActivities() {
        guard let api else { return }
        let now = Date()

        let candidates = activeIDs.filter { id in
            if seeding.contains(id) { return false }
            if let last = seedAttempts[id], now.timeIntervalSince(last) < 30 { return false }
            guard let activity = liveActivity[id] else { return true }
            return now.timeIntervalSince(activity.updatedAt) > 60
        }

        for id in candidates {
            seeding.insert(id)
            seedAttempts[id] = now
            let directory = sessions.first(where: { $0.id == id })?.directory

            Task { [weak self] in
                let response = try? await api.sessionMessages(id: id, limit: 20)
                guard let self else { return }
                self.seeding.remove(id)
                guard let derived = response.flatMap({
                    SessionActivity.derive(from: $0.data, directory: directory)
                }) else { return }

                // A snapshot built from older messages must never overwrite
                // activity that an event has already made newer.
                if let existing = self.liveActivity[id], existing.updatedAt > derived.updatedAt { return }
                self.liveActivity[id] = derived
            }
        }
    }

    func handle(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        DevLog.shared.record(
            "Connection error",
            category: .app,
            level: .error,
            detail: message
        )
        if let apiError = error as? APIError, apiError.shouldRediscover {
            // Port or credentials likely changed; rediscover on the next poll.
            api = nil
            location = nil
            eventTask?.cancel()
            eventTask = nil
            connection = .offline("Reconnecting…")
            return
        }
        connection = .offline(message)
    }
}
