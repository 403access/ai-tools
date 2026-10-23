import Combine
import Foundation

extension MobileStore {
    // MARK: - Events

    func startEvents(location: HubLocation) {
        eventTask?.cancel()
        eventTask = HubEventStream.connect(baseURL: location.url, token: location.token) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    func handle(_ event: OpenCodeEvent) {
        if event.type == "server.connected" || event.type == "hub.connected" {
            if eventStreamConnected {
                seedAttempts.removeAll()
                for id in Array(liveActivity.keys) {
                    liveActivity[id]?.updatedAt = .distantPast
                }
            }
            eventStreamConnected = true
        }

        if event.type == "hub.usage" {
            Task { await refreshUsage() }
        }
        if event.type == "hub.stats" {
            Task { await refreshStats(force: true) }
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

    func scheduleLiveRefresh() {
        guard debounceTask == nil else { return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else {
                self?.debounceTask = nil
                return
            }
            await self?.refreshLive()
            self?.debounceTask = nil
        }
    }

    func applyUsage(_ data: OpenCodeEvent.Payload?, to id: String) {
        guard let data, let cost = data.cost, let tokens = data.tokens else { return }
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].cost = cost
            sessions[index].tokens = tokens
            updateDerivedSession(sessions[index])
            database?.upsertSessions([sessions[index]])
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

    func pruneActivity() {
        let cutoff = Date().addingTimeInterval(-10)
        liveActivity = liveActivity.filter { id, activity in
            activeIDs.contains(id) || activity.updatedAt > cutoff
        }
        seedAttempts = seedAttempts.filter { activeIDs.contains($0.key) }
    }

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
                if let existing = self.liveActivity[id], existing.updatedAt > derived.updatedAt { return }
                self.liveActivity[id] = derived
            }
        }
    }
}
