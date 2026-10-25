import Foundation

extension AppState {
    // MARK: - Refresh

    func refreshAll() async {
        // These endpoints are independent; issuing them together keeps the
        // initial panel load roughly as fast as the slowest one instead of
        // adding their latencies.
        async let live: Void = refreshLive()
        async let stats: Void = refreshStats(force: true)
        async let history: Void = refreshHistory(force: true)
        async let usage: Void = refreshGoUsage()
        _ = await (live, stats, history, usage)
        if let project = selectedProject { await loadProject(project.id, force: true) }
    }

    func refreshLive() async {
        guard let api else {
            await bootstrap()
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let active = api.activeSessionIDs()
            async let recent = api.sessions(limit: 60)
            async let projectList = api.projects()

            let (activeIDs, recentSessions, projectListValue) = try await (active, recent, projectList)

            let newActiveIDs = Set(activeIDs)
            var merged = recentSessions
            let present = Set(recentSessions.map(\.id))
            let missing = activeIDs.filter { !present.contains($0) }
            if !missing.isEmpty {
                // A running session can briefly be absent from the recent page.
                // Fetch the stragglers concurrently instead of serially.
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
                merged.append(contentsOf: fetched)
            }

            let newSessions = SessionOrdering.mostRecentFirst(merged)
            let newProjects = Dictionary(projectListValue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            if newActiveIDs != self.activeIDs { self.activeIDs = newActiveIDs }
            if newSessions != self.sessions { self.sessions = newSessions }
            if newProjects != self.projects { self.projects = newProjects }
            self.pruneActivity()
            self.rebuildDerived()
            self.syncSubagentLists(with: newSessions)

            if let selected = selectedSession,
               let updated = newSessions.first(where: { $0.id == selected.id }) {
                selectedSession = updated
            }

            if let selected = selectedProject, let updated = self.projects[selected.id] {
                selectedProject = updated
            }

            if case .connected = connection {
                // keep current version
            } else {
                let info = try? await api.serverInfo()
                connection = .connected(version: info?.version ?? "?")
            }
            lastUpdated = Date()
        } catch {
            handle(error)
        }

        seedActivities()
    }

    /// Loads the System tab's snapshot. The hub caches expensive sections, so
    /// the tab can poll this every few seconds without hammering the machine.
    func refreshSystemInfo(force: Bool = false) async {
        if api == nil { await bootstrap() }
        guard let api else { return }
        guard !isRefreshingSystemInfo else { return }
        if !force, let fetched = systemInfoFetchedAt,
           Date().timeIntervalSince(fetched) < 4 {
            return
        }

        isRefreshingSystemInfo = true
        defer { isRefreshingSystemInfo = false }

        do {
            let snapshot = try await api.systemInfo(force: force)
            systemInfo = snapshot
            systemInfoFetchedAt = Date()
            systemInfoError = nil
        } catch {
            if let apiError = error as? APIError, case .request(404, _) = apiError {
                systemInfoError = "This hub does not serve system information yet. Restart it with the latest code."
            } else {
                // Keep the last snapshot; the next poll usually recovers.
                systemInfoError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Sends a playback or volume action to the hub host and folds the returned
    /// media/audio state into the current snapshot immediately.
    func controlMedia(_ action: String, value: Double? = nil) async {
        if api == nil { await bootstrap() }
        guard let api else { return }
        guard !isControllingMedia else { return }
        isControllingMedia = true
        defer { isControllingMedia = false }

        let previous = systemInfo
        var expectedState: String?
        if var info = systemInfo {
            expectedState = MediaControlOptimism.apply(to: &info, action: action, value: value)
            systemInfo = info
        }

        do {
            let result = try await api.controlMedia(action: action, value: value)
            if var info = systemInfo {
                info.media = result.media
                info.audio = result.audio
                MediaControlOptimism.reconcile(&info, expectedState: expectedState)
                systemInfo = info
            }
            mediaControlError = nil
        } catch {
            if let previous { systemInfo = previous }
            mediaControlError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Loads the Settings tab: connected client apps plus hub/server details.
    func refreshSettings(force: Bool = false) async {
        guard let api else {
            await bootstrap()
            return
        }
        if isRefreshingSettings { return }
        if !force, let fetched = settingsUpdatedAt, Date().timeIntervalSince(fetched) < 10 {
            return
        }

        isRefreshingSettings = true
        defer { isRefreshingSettings = false }

        do {
            async let devices = api.devices()
            async let info = api.serverInfo()
            async let health = api.health()
            let (deviceList, serverInfo, serverHealth) = try await (devices, info, health)
            self.devices = deviceList
            self.hubInfo = serverInfo
            self.hubHealth = serverHealth
            // Hubs that predate the settings endpoint still expose devices and
            // health, so a missing payload must not fail the whole refresh.
            if let settings = try? await api.settings() {
                self.serverSettings = settings
            }
            self.settingsUpdatedAt = Date()
            self.settingsError = nil
        } catch {
            self.settingsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Changes how often the hub forwards event updates to the connected apps.
    /// A larger window relieves pressure from streaming sessions at the cost of
    /// slightly less immediate live rows.
    func updateEventThrottle(_ milliseconds: Int) async {
        guard let api else {
            await bootstrap()
            return
        }
        guard !isUpdatingSettings else { return }
        isUpdatingSettings = true
        defer { isUpdatingSettings = false }

        do {
            let settings = try await api.updateSettings(eventThrottleMs: milliseconds)
            self.serverSettings = settings
            self.settingsError = nil
            self.settingsNotice = settings.eventThrottleMs == 0
                ? "Live updates are sent immediately"
                : "Updates throttled to \(settings.eventThrottleMs) ms"
        } catch {
            settingsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Keeps the hub host awake (or lets it sleep normally). Blocking idle
    /// sleep preserves the phone's connection when the Mac would otherwise
    /// suspend the hub.
    func updatePreventSleep(_ enabled: Bool) async {
        guard let api else {
            await bootstrap()
            return
        }
        guard !isUpdatingSettings else { return }
        isUpdatingSettings = true
        defer { isUpdatingSettings = false }

        do {
            let settings = try await api.updateSettings(preventSleep: enabled)
            self.serverSettings = settings
            self.settingsError = nil
            self.settingsNotice = settings.preventSleep == true
                ? "The Mac will stay awake while the hub runs"
                : "The Mac can sleep normally"
        } catch {
            settingsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Asks the hub to pull fresh OpenCode data, then refreshes the panel.
    func syncNow() async {
        guard let api else {
            await bootstrap()
            return
        }
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await api.sync()
            settingsNotice = "Synced with OpenCode"
            await refreshAll()
            await refreshSettings(force: true)
        } catch {
            settingsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Restarts the hub process and reconnects once it is back. Used by the
    /// Settings tab's server controls.
    func restartServer() async {
        guard let api else {
            await bootstrap()
            return
        }
        guard !isRestartingServer else { return }
        isRestartingServer = true
        settingsError = nil
        settingsNotice = "Restarting hub…"
        defer { isRestartingServer = false }

        do {
            try await api.restartServer()
        } catch {
            // The process may exit before the request finishes; the reconnect
            // below is the real health check.
        }

        try? await Task.sleep(nanoseconds: 1_500_000_000)

        eventTask?.cancel()
        eventTask = nil
        self.api = nil
        self.location = nil
        connection = .connecting
        await bootstrap()
        await refreshSettings(force: true)

        if case .offline(let reason) = connection {
            settingsError = "Hub did not come back: \(reason)"
        } else {
            settingsNotice = "Hub restarted"
        }
    }

    /// Publishes the last known numbers immediately, so the Usage tab has
    /// something to show before — or instead of — a successful fetch.
    func restoreCachedUsage() {
        cache = UsageCache.load()
        if let cached = cache.stats {
            stats = cached
            statsFetchedAt = cache.statsFetchedAt
        }
        if let usage = cache.goUsage {
            goUsage = .ready(usage)
            goUsageFetchedAt = cache.goUsageFetchedAt
        }
    }

    func refreshStats(force: Bool = false) async {
        guard let api else {
            // Offline: whatever we have — in memory or restored from disk —
            // is all there is to show.
            if stats != nil { statsStale = true }
            return
        }
        if !force, let fetched = statsFetchedAt, Date().timeIntervalSince(fetched) < 30 { return }
        do {
            let fresh = try await api.stats()
            stats = fresh
            statsFetchedAt = Date()
            statsStale = false
            cache.stats = fresh
            cache.statsFetchedAt = statsFetchedAt
            cache.save()
        } catch {
            // Keep the last known stats; a later refresh will recover.
            if stats != nil { statsStale = true }
        }
    }

    /// Fetches the full session list for the usage charts. Kept separate from
    /// `refreshLive` so the 5s live poll stays small; this runs on the 60s cycle.
    func refreshHistory(force: Bool = false) async {
        guard let api else { return }
        if !force, let fetched = historyFetchedAt,
           Date().timeIntervalSince(fetched) < 60 {
            return
        }
        do {
            history = SessionOrdering.mostRecentFirst(try await api.sessions(limit: 1_000))
            historyFetchedAt = Date()
        } catch {
            // Keep the last known history; the charts still work with it.
        }
    }

    /// Fetches Go plan quota from the hub, which owns the usage key and keeps a
    /// last-known-good copy in SQLite. Cheap when no key is configured: the hub
    /// says so without making a request.
    func refreshGoUsage() async {
        guard let api else { return }
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }
        switch goUsage {
        case .ready, .stale:
            break // Keep showing the current numbers while refreshing.
        case .unavailable, .loading, .failed:
            goUsage = .loading
        }
        do {
            let response = try await api.usage()
            guard response.configured else {
                goUsage = .unavailable
                goUsageFetchedAt = nil
                return
            }
            if let usage = response.data {
                if let error = response.error, !error.isEmpty {
                    goUsage = .stale(usage, reason: error)
                } else {
                    goUsage = .ready(usage)
                }
                goUsageFetchedAt = response.fetchedDate ?? Date()
                cache.goUsage = usage
                cache.goUsageFetchedAt = goUsageFetchedAt
                cache.save()
            } else if let error = response.error {
                if let cached = cache.goUsage {
                    goUsage = .stale(cached, reason: error)
                } else {
                    goUsage = .failed(error)
                }
            } else {
                goUsage = .unavailable
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let cached = cache.goUsage {
                goUsage = .stale(cached, reason: message)
            } else {
                goUsage = .failed(message)
            }
        }
    }

    func scheduleLiveRefresh() {
        // Throttle instead of debounce: a busy event stream cancels a debounce
        // forever, so the list would not refresh until it went quiet. One
        // scheduled refresh at a time keeps the poll responsive under load.
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
}
