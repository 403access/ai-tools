import Foundation

/// Single source of truth for the panel. Polls the service on a slow cadence,
/// subscribes to the event stream for instant updates, and recovers
/// automatically if the background service restarts on a new port.
@MainActor
final class AppState: ObservableObject {
    enum Connection: Equatable {
        case connecting
        case connected(version: String)
        case offline(String)

        var label: String {
            switch self {
            case .connecting: return "Connecting…"
            case .connected(let version): return "Connected · v\(version)"
            case .offline(let reason): return reason
            }
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case live = "Live"
        case usage = "Usage"
        case projects = "Projects"
        case settings = "Settings"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .usage: return "chart.bar.xaxis"
            case .projects: return "folder"
            case .settings: return "gearshape"
            }
        }
    }

    /// Everything a project detail page knows about one project, fetched on
    /// demand the first time the project is opened.
    struct ProjectDetail: Equatable {
        var stats: Stats?
        var sessions: [Session] = []
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

    /// Direct child sessions of a session, fetched on demand for the Subagents
    /// tab.
    struct SubagentList: Equatable {
        var sessions: [Session] = []
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

    struct ChangesState: Equatable {
        var changes: [FileChange] = []
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

    struct ProjectFilesState: Equatable {
        var files: ProjectFiles?
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

    struct SessionStatsState: Equatable {
        var stats: SessionStats?
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

    /// Sections available in the session detail view.
    enum DetailMode: String, CaseIterable, Identifiable {
        case conversation = "Conversation"
        case stats = "Stats"
        case changes = "Changes"
        case prompts = "Prompts"
        case subagents = "Subagents"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .conversation: return "bubble.left.and.bubble.right"
            case .stats: return "wrench.and.screwdriver"
            case .changes: return "plus.forwardslash.minus"
            case .prompts: return "text.quote"
            case .subagents: return "person.2"
            }
        }
    }

    @Published var connection: Connection = .connecting
    @Published var tab: Tab = .live
    @Published var sessions: [Session] = []
    /// Full session history, refreshed on the slow cycle. The live list only
    /// holds the newest sessions; the trend charts need the older ones too.
    @Published var history: [Session] = []
    @Published var activeIDs: Set<String> = []
    @Published var projects: [String: Project] = [:]
    @Published var stats: Stats?
    @Published var statsStale = false
    @Published var goUsage: GoUsageState = .unavailable
    @Published var goUsageFetchedAt: Date?
    /// Live "what is it doing" snapshot for each active session, folded from
    /// the event stream and reseeded from messages when needed.
    @Published var liveActivity: [String: SessionActivity] = [:]
    @Published var projectDetails: [String: ProjectDetail] = [:]
    /// File patches written by each session, loaded when the Changes tab opens.
    @Published var sessionChanges: [String: ChangesState] = [:]
    /// Project-wide changes, aggregated across its newest sessions.
    @Published var projectChanges: [String: ChangesState] = [:]
    /// Files inside each project folder, with git working-tree status.
    @Published var projectFiles: [String: ProjectFilesState] = [:]
    /// Per-session stats (prompts, tool reliability, failures), loaded when the
    /// Stats tab opens.
    @Published var sessionStats: [String: SessionStatsState] = [:]
    /// Child sessions per parent, loaded when a session's Subagents tab is
    /// opened and kept in sync with the live session list.
    @Published var subagentLists: [String: SubagentList] = [:]
    /// Mac and iOS apps known to the hub, with their live state.
    @Published var devices: [ConnectedDevice] = []
    /// Server information shown on the Settings tab.
    @Published var hubInfo: ServerInfo?
    @Published var hubHealth: HubHealthResponse?
    /// Tunable hub behaviour, such as the event-stream throttle.
    @Published var serverSettings: ServerSettings?
    @Published var settingsError: String?
    @Published var settingsNotice: String?
    @Published var isRefreshingSettings = false
    @Published var isUpdatingSettings = false
    @Published var isSyncing = false
    @Published var isRestartingServer = false
    @Published private(set) var settingsUpdatedAt: Date?
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    /// Derived feeds, rebuilt once per refresh instead of being filtered and
    /// sorted every time a view reads them.
    @Published private(set) var runningSessions: [Session] = []
    @Published private(set) var recentSessions: [Session] = []
    @Published private(set) var orderedProjects: [Project] = []
    private var runningByProject: [String: [Session]] = [:]
    private var subagentCounts: [String: Int] = [:]
    private var projectNames: [String: String] = [:]
    /// Session whose detail view is open, if any. Kept in sync with the
    /// session list so a running session's header keeps updating.
    @Published var selectedSession: Session?
    /// Sessions above the current one when drilling into subagents. The last
    /// element is the back destination.
    private(set) var sessionStack: [Session] = []
    /// Project whose detail page is open, if any. Kept in sync with the project
    /// list. A session opened from the project detail page leaves this set, so
    /// closing the session returns to the project.
    @Published var selectedProject: Project?
    /// Section the detail view opens on. Overridable from the command line for
    /// previews/screenshots (`--detail-mode prompts`).
    var detailMode: DetailMode = .conversation

    /// Connection details for the Settings tab. The token stays in memory and is
    /// only used to build the pairing link on request.
    var hubLocation: HubLocation? { location }

    var pairingLink: String? {
        guard let location else { return nil }
        var components = URLComponents()
        components.scheme = "opencodebar"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "url", value: pairingHubURL(fallingBackTo: location.url).absoluteString),
            URLQueryItem(name: "token", value: location.token),
        ]
        return components.string
    }

    /// The hub address a phone should use. The Mac connects over loopback, so
    /// prefer one of the LAN URLs the hub reports; otherwise the QR code and
    /// link would point the phone at itself. A non-loopback override is already
    /// reachable from the phone and is kept as-is.
    private func pairingHubURL(fallingBackTo fallback: URL) -> URL {
        guard isLoopback(fallback) else { return fallback }
        // A running `make hub-tunnel` URL works from cellular, where the Mac's
        // LAN address is unreachable.
        if let tunnel = HubDiscovery.activeTunnelURL() { return tunnel }
        let lan = hubInfo?.urls?.compactMap(URL.init(string:)).first { !isLoopback($0) }
        return lan ?? fallback
    }

    private func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    /// Go plan quota, fetched directly from the console usage endpoint. Hidden
    /// entirely when no Go key is configured.
    enum GoUsageState: Equatable {
        case unavailable
        case loading
        case ready(GoUsage)
        /// Last known numbers, kept because the most recent fetch failed.
        case stale(GoUsage, reason: String)
        case failed(String)
    }

    @Published private(set) var statsFetchedAt: Date?

    private var api: HubAPI?
    private var location: HubLocation?
    private var cache = UsageCache()
    private var eventTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var discovering = false
    private var started = false
    private var isRefreshingUsage = false
    private var historyFetchedAt: Date?
    /// Sessions whose activity is currently being seeded from messages.
    private var seeding: Set<String> = []
    /// Last seed attempt per session, so a failed or empty fetch is not retried
    /// on every five-second poll.
    private var seedAttempts: [String: Date] = [:]
    /// Whether the event stream has connected at least once. The first
    /// connection is not a reconnect, so there is no missed history to recover.
    private var eventStreamConnected = false

    init() {
        // Allows the preview harness to open a specific tab:
        //   OpenCodeBar --preview --tab usage
        if let index = CommandLine.arguments.firstIndex(of: "--tab"),
           index + 1 < CommandLine.arguments.count,
           let requested = Tab(rawValue: CommandLine.arguments[index + 1].capitalized) {
            tab = requested
        }
        if let index = CommandLine.arguments.firstIndex(of: "--detail-mode"),
           index + 1 < CommandLine.arguments.count,
           let requested = DetailMode(rawValue: CommandLine.arguments[index + 1].capitalized) {
            detailMode = requested
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        restoreCachedUsage()
        Task { await bootstrap() }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.refreshLive()
            }
        }

        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.refreshStats(force: true)
                if self?.tab == .usage {
                    await self?.refreshHistory(force: true)
                }
                await self?.refreshSelectedProject()
                await self?.refreshSelectedSubagents()
                await self?.refreshSelectedSessionStats()
                if self?.tab == .settings {
                    await self?.refreshSettings(force: true)
                }
            }
        }

        usageTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshGoUsage()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    private func bootstrap() async {
        guard !discovering else { return }
        discovering = true
        defer { discovering = false }

        guard let location = await discover() else {
            connection = .offline("Hub not found")
            settingsError = "Hub not found. Run `make hub` or check ~/.config/opencode/opencodebar-hub.json."
            if stats != nil { statsStale = true }
            return
        }
        self.location = location
        self.api = HubAPI(location: location)
        // Connect before the slower history/stats fetches so live events from
        // the first seconds after launch are not missed.
        startEvents()
        await refreshAll()
        // The Settings tab may have asked before discovery finished; its guard
        // would otherwise leave the page empty until the next manual refresh.
        if tab == .settings {
            await refreshSettings(force: true)
        }
    }

    private func discover() async -> HubLocation? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: HubDiscovery.load())
            }
        }
    }

    private func startEvents() {
        guard let location, eventTask == nil else { return }
        eventTask = HubEventStream.connect(
            baseURL: location.url,
            token: location.token
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

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
    private func restoreCachedUsage() {
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

    private func scheduleLiveRefresh() {
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

    // MARK: - Live activity

    func activity(for sessionID: String) -> SessionActivity? {
        liveActivity[sessionID]
    }

    /// Fetches a single session by ID, for deep links and preview tooling.
    func fetchSession(id: String) async -> Session? {
        guard let api else { return nil }
        return try? await api.session(id: id)
    }

    /// Folds an event into the matching session's activity, updates live
    /// cost/tokens, and refreshes the list (debounced) as before.
    private func handle(_ event: OpenCodeEvent) {
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
    private func applyUsage(_ data: OpenCodeEvent.Payload?, to id: String) {
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
    private func pruneActivity() {
        let cutoff = Date().addingTimeInterval(-10)
        liveActivity = liveActivity.filter { id, activity in
            activeIDs.contains(id) || activity.updatedAt > cutoff
        }
        seedAttempts = seedAttempts.filter { activeIDs.contains($0.key) }
    }

    /// Rebuilds activity from the newest messages when the panel starts, when
    /// the event stream reconnects, or when a session has gone quiet for long
    /// enough that a missed event is plausible.
    private func seedActivities() {
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

    private func handle(_ error: Error) {
        if let apiError = error as? APIError, apiError.shouldRediscover {
            // Port or credentials likely changed; rediscover on the next poll.
            api = nil
            location = nil
            eventTask?.cancel()
            eventTask = nil
            connection = .offline("Reconnecting…")
            return
        }
        connection = .offline((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    }

    // MARK: - Session detail

    /// Opens a session. Passing `from` when drilling into a subagent pushes the
    /// parent onto the back stack; opening from the Live tab or a project
    /// starts a fresh stack.
    func open(_ session: Session, from parent: Session? = nil) {
        if let parent, parent.id != session.id {
            if sessionStack.last?.id != parent.id {
                sessionStack.append(parent)
            }
        } else {
            sessionStack.removeAll()
        }
        selectedSession = session
        Task { await loadSubagents(session.id) }
    }

    func closeDetail() {
        if let previous = sessionStack.popLast() {
            selectedSession = sessions.first(where: { $0.id == previous.id }) ?? previous
        } else {
            selectedSession = nil
        }
    }

    /// Title of the session detail view's back button. A drilled-in session
    /// returns to its parent; everything else returns to the project or Live.
    var sessionBackTitle: String {
        if let previous = sessionStack.last {
            let latest = sessions.first(where: { $0.id == previous.id }) ?? previous
            return latest.displayTitle
        }
        return selectedProject?.displayName ?? "Live"
    }

    func isRunning(_ session: Session) -> Bool {
        activeIDs.contains(session.id)
    }

    /// Fetches conversation messages, newest first. Pass a cursor from a
    /// previous response to page further back in the session.
    func messages(
        for sessionID: String,
        limit: Int = 100,
        cursor: String? = nil
    ) async throws -> SessionMessagesResponse {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        return try await api.sessionMessages(id: sessionID, limit: limit, cursor: cursor)
    }

    /// Creates a session in `directory` and opens it. Used by the New Session
    /// sheet on the Live and Project detail views.
    func createSession(title: String?, directory: String) async throws -> Session {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        let session = try await api.createSession(title: title, directory: directory)
        sessions.insert(session, at: 0)
        rebuildDerived()
        sessionStack.removeAll()
        selectedSession = session
        await refreshLive()
        return session
    }

    /// Sends a prompt into an open session. Running sessions queue the message
    /// by default so it does not interrupt the current turn.
    func promptSession(
        id: String,
        text: String,
        delivery: PromptDelivery? = nil
    ) async throws {
        guard let api else { throw APIError.transport("Not connected to OpenCode") }
        try await api.promptSession(id: id, text: text, delivery: delivery)
        activeIDs.insert(id)
        rebuildDerived()
        await refreshLive()
    }

    /// Fetches the file patches written by a session. The hub hydrates message
    /// history on demand, so the first call may page through a long session.
    func loadChanges(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionChanges[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionChanges[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&sessionChanges, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionChanges[sessionID] ?? ChangesState()
        state.isLoading = true
        state.error = nil
        sessionChanges[sessionID] = state

        do {
            let changes = try await api.sessionChanges(id: sessionID)
            sessionChanges[sessionID] = ChangesState(changes: changes, loadedAt: Date())
        } catch {
            var failed = sessionChanges[sessionID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                sessionChanges[sessionID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionChanges[sessionID] = failed
        }
    }

    /// Fetches a session's tool-use and failure summary. The hub hydrates the
    /// message history on the first request, so this can take a moment.
    func loadSessionStats(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionStats[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionStats[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&sessionStats, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionStats[sessionID] ?? SessionStatsState()
        state.isLoading = true
        state.error = nil
        sessionStats[sessionID] = state

        do {
            let stats = try await api.sessionStats(id: sessionID)
            sessionStats[sessionID] = SessionStatsState(stats: stats, loadedAt: Date())
        } catch {
            var failed = sessionStats[sessionID] ?? SessionStatsState()
            failed.isLoading = false
            if Task.isCancelled {
                sessionStats[sessionID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            sessionStats[sessionID] = failed
        }
    }

    /// Refreshes the open session's stats on the slow cycle.
    private func refreshSelectedSessionStats() async {
        guard let id = selectedSession?.id, sessionStats[id]?.stats != nil else { return }
        await loadSessionStats(id, force: true)
    }

    /// Fetches changes across a project's newest sessions.
    func loadProjectChanges(_ projectID: String, force: Bool = false) async {
        guard let api else { return }
        if projectChanges[projectID]?.isLoading == true { return }
        if !force, let loaded = projectChanges[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectChanges, loadedAt: { $0.loadedAt }, pinning: projectID) }

        var state = projectChanges[projectID] ?? ChangesState()
        state.isLoading = true
        state.error = nil
        projectChanges[projectID] = state

        do {
            let changes = try await api.projectChanges(id: projectID)
            projectChanges[projectID] = ChangesState(changes: changes, loadedAt: Date())
        } catch {
            var failed = projectChanges[projectID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                projectChanges[projectID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectChanges[projectID] = failed
        }
    }

    /// Fetches the files in a project folder. The hub reads the directory and
    /// reports git working-tree status, so this is refreshed when the page
    /// reopens or the user asks for a refresh.
    func loadProjectFiles(_ projectID: String, force: Bool = false) async {
        guard let api else { return }
        if projectFiles[projectID]?.isLoading == true { return }
        if !force, let loaded = projectFiles[projectID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectFiles, loadedAt: { $0.loadedAt }, pinning: projectID) }

        var state = projectFiles[projectID] ?? ProjectFilesState()
        state.isLoading = true
        state.error = nil
        projectFiles[projectID] = state

        do {
            let files = try await api.projectFiles(id: projectID)
            projectFiles[projectID] = ProjectFilesState(files: files, loadedAt: Date())
        } catch {
            var failed = projectFiles[projectID] ?? ProjectFilesState()
            failed.isLoading = false
            if Task.isCancelled {
                projectFiles[projectID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectFiles[projectID] = failed
        }
    }

    // MARK: - Projects

    /// Opens the full detail page for a project, loading its scoped stats and
    /// recent sessions on demand.
    func open(_ project: Project) {
        sessionStack.removeAll()
        selectedProject = project
        Task { await loadProject(project.id) }
    }

    func closeProject() {
        sessionStack.removeAll()
        selectedProject = nil
    }

    func loadProject(_ id: String, force: Bool = false) async {
        guard let api else { return }
        if !force, projectDetails[id]?.isLoading == true { return }
        if !force, let detail = projectDetails[id], let loaded = detail.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&projectDetails, loadedAt: { $0.loadedAt }, pinning: id) }

        projectDetails[id, default: ProjectDetail()].isLoading = true
        do {
            async let stats = api.stats(project: id)
            async let sessions = api.sessions(projectID: id, limit: 1_000)
            let (scopedStats, recent) = try await (stats, sessions)
            projectDetails[id] = ProjectDetail(
                stats: scopedStats,
                sessions: SessionOrdering.mostRecentFirst(recent),
                loadedAt: Date()
            )
        } catch {
            var detail = projectDetails[id] ?? ProjectDetail()
            detail.isLoading = false
            detail.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            projectDetails[id] = detail
        }
    }

    private func refreshSelectedProject() async {
        guard let project = selectedProject else { return }
        if let updated = projects[project.id] { selectedProject = updated }
        await loadProject(project.id, force: true)
        await loadProjectChanges(project.id, force: true)
        await loadProjectFiles(project.id, force: true)
    }

    // MARK: - Subagents

    func subagentList(for parentID: String) -> SubagentList? {
        subagentLists[parentID]
    }

    func hasSubagents(_ parentID: String) -> Bool {
        !(subagentLists[parentID]?.sessions.isEmpty ?? true)
    }

    func isLoadingSubagents(_ parentID: String) -> Bool {
        subagentLists[parentID]?.isLoading == true
    }

    /// Fetches the direct child sessions of a parent. Each level is loaded when
    /// it is opened, so drilling into a child loads that child's own subagents.
    func loadSubagents(_ parentID: String, force: Bool = false) async {
        guard let api else {
            DebugLog.subagents("[subagents] no api \(parentID)")
            return
        }
        if subagentLists[parentID]?.isLoading == true { return }
        if !force, let loaded = subagentLists[parentID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&subagentLists, loadedAt: { $0.loadedAt }, pinning: parentID) }

        DebugLog.subagents("[subagents] start \(parentID)")

        var list = subagentLists[parentID] ?? SubagentList()
        list.isLoading = true
        list.error = nil
        subagentLists[parentID] = list

        do {
            let children = try await api.sessions(parentID: parentID, limit: 50)
            DebugLog.subagents("[subagents] done \(parentID) \(children.count)")
            subagentLists[parentID] = SubagentList(
                sessions: SubagentOrdering.sorted(children, activeIDs: activeIDs),
                loadedAt: Date()
            )
        } catch {
            var failed = subagentLists[parentID] ?? SubagentList()
            failed.isLoading = false
            if Task.isCancelled {
                // Navigating away cancels the view's task; do not surface that
                // as a load failure when the user comes back.
                subagentLists[parentID] = failed
                return
            }
            DebugLog.subagents("[subagents] error \(parentID) \(error)")
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            subagentLists[parentID] = failed
        }
    }

    private func refreshSelectedSubagents() async {
        guard let id = selectedSession?.id, subagentLists[id] != nil else { return }
        await loadSubagents(id, force: true)
    }

    /// Folds the five-second session list into any open subagent lists so
    /// running state and cost stay current without a second fetch.
    private func syncSubagentLists(with sessions: [Session]) {
        for parentID in Array(subagentLists.keys) {
            guard var list = subagentLists[parentID] else { continue }
            var changed = false

            for session in sessions where session.parentID == parentID {
                if let index = list.sessions.firstIndex(where: { $0.id == session.id }) {
                    if list.sessions[index] != session {
                        list.sessions[index] = session
                        changed = true
                    }
                } else {
                    list.sessions.append(session)
                    changed = true
                }
            }

            if changed {
                list.sessions = SubagentOrdering.sorted(list.sessions, activeIDs: activeIDs)
                subagentLists[parentID] = list
            }
        }
    }

    // MARK: - Derived data

    var activeCount: Int { activeIDs.count }

    /// True until the first poll has produced anything to show. Screens use it
    /// to render skeletons instead of an empty state that would flash away.
    var isInitialLoading: Bool {
        lastUpdated == nil && sessions.isEmpty && stats == nil
    }

    /// Keeps the on-demand caches bounded. Opening many sessions or projects in
    /// one run would otherwise keep every message, patch and file list alive
    /// for the life of the app.
    private func trimCache<T>(
        _ cache: inout [String: T],
        loadedAt: (T) -> Date?,
        limit: Int = 16,
        pinning key: String? = nil
    ) {
        guard cache.count > limit else { return }
        let kept = cache
            .sorted { (loadedAt($0.value) ?? .distantPast) > (loadedAt($1.value) ?? .distantPast) }
            .prefix(limit)
        var trimmed = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        if let key, let pinned = cache[key] { trimmed[key] = pinned }
        cache = trimmed
    }

    /// Rebuilds the feeds the views read. Called after the session list,
    /// running set or project map changes, so filtering and sorting happen once
    /// per refresh instead of on every view body evaluation.
    private func rebuildDerived() {
        var running: [Session] = []
        var recent: [Session] = []
        running.reserveCapacity(min(sessions.count, activeIDs.count))
        recent.reserveCapacity(sessions.count)
        for session in sessions {
            if activeIDs.contains(session.id) {
                running.append(session)
            } else {
                recent.append(session)
            }
        }
        running.sort { $0.time.updated > $1.time.updated }
        recent.sort { $0.time.updated > $1.time.updated }

        if running != runningSessions { runningSessions = running }
        if recent != recentSessions { recentSessions = recent }

        runningByProject = ProjectOrdering.runningByProject(sessions: sessions, activeIDs: activeIDs)
        var counts: [String: Int] = [:]
        for session in sessions where activeIDs.contains(session.id) {
            if let parentID = session.parentID {
                counts[parentID, default: 0] += 1
            }
        }
        subagentCounts = counts

        let ordered = ProjectOrdering.ordered(
            projects: projects,
            runningCounts: runningByProject.mapValues(\.count)
        )
        if ordered != orderedProjects { orderedProjects = ordered }

        var names: [String: String] = [:]
        names.reserveCapacity(projects.count)
        for project in projects.values {
            names[project.id] = project.displayName
        }
        projectNames = names
    }

    /// Keeps the derived feeds in step when a single session's cost or tokens
    /// move on an event, without rebuilding and re-sorting the whole list.
    private func updateDerivedSession(_ session: Session) {
        if let index = runningSessions.firstIndex(where: { $0.id == session.id }) {
            runningSessions[index] = session
        }
        if let index = recentSessions.firstIndex(where: { $0.id == session.id }) {
            recentSessions[index] = session
        }
    }

    func runningSessions(in project: Project) -> [Session] {
        runningByProject[project.id] ?? []
    }

    func activeSubagentCount(for sessionID: String) -> Int {
        subagentCounts[sessionID] ?? 0
    }

    func projectName(for session: Session) -> String {
        if let name = projectNames[session.projectID] { return name }
        return Fmt.projectName(for: session, projects: projects)
    }

    var todaySteps: Int {
        stats?.steps(onDay: Fmt.dayString(Date())) ?? 0
    }
}
