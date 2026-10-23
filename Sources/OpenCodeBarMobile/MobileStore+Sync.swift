import Combine
import Foundation

extension MobileStore {
    // MARK: - Refresh

    func refreshAll() async {
        async let live: Void = refreshLive()
        async let stats: Void = refreshStats(force: true)
        async let usage: Void = refreshUsage(force: true)
        _ = await (live, stats, usage)
    }

    /// Catches up with the hub. The first request is a full snapshot; later
    /// requests only carry rows whose revision moved.
    func refreshLive() async {
        guard let api else {
            if case .disabled = connection {} else { connection = .offline("Hub not configured") }
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let response = try await api.sync(since: cachedRevision > 0 ? cachedRevision : nil)
            apply(response)
            await fillMissingActiveSessions(response.active, api: api)
            let status = Connection.connected(version: displayVersion)
            if connection != status { connection = status }
            if hubError != nil { hubError = nil }
            // The footer only shows minute-level relative times. Republishing a
            // new Date on every 5s/750ms refresh invalidated every observing
            // tab for no visible change, so update it at most once a minute.
            let now = Date()
            if lastUpdated.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
                lastUpdated = now
            }
        } catch {
            let text = message(for: error)
            if hubError != text { hubError = text }
            let offline = Connection.offline(text)
            if connection != offline { connection = offline }
        }

        seedActivities()
        publishWidgetSnapshot()
    }

    /// Merges a delta into the in-memory store and the local database.
    func apply(_ response: HubSyncResponse) {
        let sessionsChanged = response.full
            || !response.sessions.isEmpty
            || !response.deletedSessions.isEmpty

        if sessionsChanged {
            var byID: [String: Session]
            if response.full {
                byID = Dictionary(
                    response.sessions.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            } else {
                byID = Dictionary(
                    sessions.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                for session in response.sessions { byID[session.id] = session }
                for id in response.deletedSessions { byID.removeValue(forKey: id) }
            }

            let ordered = SessionOrdering.mostRecentFirst(Array(byID.values))
            if ordered != sessions { sessions = ordered }
            syncSubagentLists(with: response.sessions)
        }

        let projectsChanged = response.full
            || !response.projects.isEmpty
            || !response.deletedProjects.isEmpty
        if projectsChanged {
            var byID: [String: Project]
            if response.full {
                byID = Dictionary(
                    response.projects.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            } else {
                byID = projects
                for project in response.projects { byID[project.id] = project }
                for id in response.deletedProjects { byID.removeValue(forKey: id) }
            }
            if byID != projects { projects = byID }
        }

        let newActive = Set(response.active)
        let activeChanged = newActive != activeIDs
        if activeChanged { activeIDs = newActive }

        // Persist before rebuilding derived feeds; the next launch hydrates from
        // exactly this snapshot.
        if response.full {
            database?.replaceSessions(sessions)
            database?.replaceProjects(Array(projects.values))
        } else {
            database?.upsertSessions(response.sessions)
            database?.deleteSessions(response.deletedSessions)
            database?.upsertProjects(response.projects)
            database?.deleteProjects(response.deletedProjects)
        }
        if cachedRevision != response.revision {
            cachedRevision = response.revision
            database?.setRevision(response.revision)
        }
        if activeChanged { database?.setActive(response.active) }

        pruneActivity()
        if sessionsChanged || projectsChanged || activeChanged {
            rebuildDerived()
        }
    }

    /// A running session older than the full snapshot window could still be
    /// missing from the local list. Fetch just those ids, as the old poll did.
    func fillMissingActiveSessions(_ active: [String], api: HubAPI) async {
        let known = Set(sessions.map(\.id))
        let missing = active.filter { !known.contains($0) }
        guard !missing.isEmpty else { return }

        let fetched = await withTaskGroup(of: Session?.self) { group in
            for id in missing {
                group.addTask { try? await api.session(id: id) }
            }
            var result: [Session] = []
            for await session in group {
                if let session { result.append(session) }
            }
            return result
        }
        guard !fetched.isEmpty else { return }

        var byID = Dictionary(
            sessions.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for session in fetched { byID[session.id] = session }
        let ordered = SessionOrdering.mostRecentFirst(Array(byID.values))
        if ordered != sessions { sessions = ordered }
        database?.upsertSessions(fetched)
        rebuildDerived()
    }

    func refreshStats(force: Bool = false) async {
        guard let api else { return }
        if !force, let fetched = statsFetchedAt, Date().timeIntervalSince(fetched) < 30 { return }
        do {
            let fresh = try await api.stats()
            if stats != fresh {
                stats = fresh
                database?.putStats(fresh)
            }
            statsFetchedAt = Date()
            if statsStale { statsStale = false }
            publishWidgetSnapshot()
        } catch {
            if stats != nil, !statsStale { statsStale = true }
        }
    }

    func refreshUsage(force: Bool = false) async {
        guard let api else { return }
        guard !isRefreshingUsage else { return }
        if !force, let fetched = usageFetchedAt, Date().timeIntervalSince(fetched) < 30 { return }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }
        do {
            let response = try await api.usage()
            usage = response
            usageFetchedAt = response.fetchedDate ?? Date()
            database?.putUsage(response)
            publishWidgetSnapshot()
        } catch {
            // Keep the last response; the view shows its existing state.
        }
    }

    func refreshHealth() async {
        guard let api else { return }
        guard !isRefreshingHealth else { return }
        isRefreshingHealth = true
        defer { isRefreshingHealth = false }
        do {
            let health = try await api.health()
            hubHealth = health
            hubVersion = health.opencode?.version ?? health.hub?.version
        } catch {
            // The connection status is already surfaced by refreshLive.
        }
    }
}
