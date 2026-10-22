import Combine
import Foundation

/// Observable state for the iOS app. Talks only to the hub: it polls the cached
/// REST endpoints, subscribes to the forwarded event stream, and folds events
/// into the same live-activity snapshots the Mac app uses.
@MainActor
final class MobileStore: ObservableObject {
    enum Connection: Equatable {
        case disabled
        case connecting
        case connected(version: String)
        case offline(String)

        var label: String {
            switch self {
            case .disabled: return "Not configured"
            case .connecting: return "Connecting…"
            case .connected(let version): return "Connected · v\(version)"
            case .offline(let reason): return reason
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    struct ProjectDetail: Equatable {
        var stats: Stats?
        var sessions: [Session] = []
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

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
    @Published var sessions: [Session] = []
    @Published var activeIDs: Set<String> = []
    @Published var projects: [String: Project] = [:]
    @Published var stats: Stats?
    @Published var statsStale = false
    @Published var history: [Session] = []
    @Published var usage: HubUsageResponse?
    @Published var usageFetchedAt: Date?
    @Published var hubHealth: HubHealthResponse?
    @Published var liveActivity: [String: SessionActivity] = [:]
    @Published var projectDetails: [String: ProjectDetail] = [:]
    @Published var sessionChanges: [String: ChangesState] = [:]
    @Published var projectChanges: [String: ChangesState] = [:]
    @Published var projectFiles: [String: ProjectFilesState] = [:]
    @Published var sessionStats: [String: SessionStatsState] = [:]
    @Published var subagentLists: [String: SubagentList] = [:]
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    @Published var hubError: String?
    /// Derived feeds, rebuilt once per refresh instead of on every read.
    @Published private(set) var runningSessions: [Session] = []
    @Published private(set) var recentSessions: [Session] = []
    @Published private(set) var orderedProjects: [Project] = []
    private var runningByProject: [String: [Session]] = [:]
    private var subagentCounts: [String: Int] = [:]
    private var projectNames: [String: String] = [:]

    private let settingsStore: HubSettingsStore
    private var api: HubAPI?
    private var hubVersion: String?
    private var liveTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var started = false
    private var statsFetchedAt: Date?
    private var historyFetchedAt: Date?
    private var seeding: Set<String> = []
    private var seedAttempts: [String: Date] = [:]
    private var eventStreamConnected = false
    private var isRefreshingUsage = false
    private var isRefreshingHealth = false
    private var isPaused = false

    init(settings: HubSettingsStore) {
        self.settingsStore = settings
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        isPaused = false

        guard let location = settingsStore.settings.location else {
            connection = .disabled
            return
        }

        connection = .connecting
        api = HubAPI(location: location)
        startEvents(location: location)
        Task { await bootstrap() }
        startTimers()
    }

    /// The polling loops, split out so they can be paused when the app is
    /// backgrounded without tearing down the connection state.
    private func startTimers() {
        guard liveTask == nil else { return }

        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.refreshLive()
            }
        }

        slowTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.refreshStats(force: true)
                await self?.refreshHistory(force: true)
                await self?.refreshUsage(force: true)
            }
        }
    }

    /// Stops network work while the app is in the background. The cached data
    /// stays in memory so the first frame back is instant.
    func pause() {
        isPaused = true
        liveTask?.cancel()
        slowTask?.cancel()
        eventTask?.cancel()
        debounceTask?.cancel()
        liveTask = nil
        slowTask = nil
        eventTask = nil
        debounceTask = nil
    }

    /// Reconnects the event stream and resumes polling after returning to the
    /// foreground, then refreshes once so stale data is corrected immediately.
    func resume() {
        guard started, isPaused else { return }
        isPaused = false
        if eventTask == nil, let location = settingsStore.settings.location {
            startEvents(location: location)
        }
        startTimers()
        Task { await refreshAll() }
    }

    func stop() {
        started = false
        pause()
        api = nil
    }

    /// Applies saved settings and starts over. Used after the setup screen saves.
    func reconnect() {
        stop()
        sessions = []
        activeIDs = []
        projects = [:]
        stats = nil
        history = []
        usage = nil
        usageFetchedAt = nil
        hubHealth = nil
        liveActivity = [:]
        projectDetails = [:]
        sessionChanges = [:]
        projectChanges = [:]
        projectFiles = [:]
        sessionStats = [:]
        subagentLists = [:]
        lastUpdated = nil
        statsFetchedAt = nil
        historyFetchedAt = nil
        hubError = nil
        eventStreamConnected = false
        seedAttempts = [:]
        seeding = []
        runningSessions = []
        recentSessions = []
        orderedProjects = []
        runningByProject = [:]
        subagentCounts = [:]
        projectNames = [:]
        connection = .connecting
        start()
    }

    /// Stops polling and clears the connection after the user removes the hub
    /// configuration.
    func disconnect() {
        stop()
        connection = .disabled
        hubHealth = nil
    }

    private func bootstrap() async {
        guard let api else { return }
        do {
            let health = try await api.health()
            hubHealth = health
            hubVersion = health.opencode?.version ?? health.hub?.version
            connection = .connected(version: displayVersion)
            hubError = nil
        } catch {
            connection = .offline(message(for: error))
            hubError = message(for: error)
        }
        await refreshAll()
    }

    private var displayVersion: String {
        hubHealth?.opencode?.version ?? hubHealth?.hub?.version ?? hubVersion ?? "hub"
    }

    // MARK: - Refresh

    func refreshAll() async {
        async let live: Void = refreshLive()
        async let stats: Void = refreshStats(force: true)
        async let history: Void = refreshHistory(force: true)
        async let usage: Void = refreshUsage(force: true)
        _ = await (live, stats, history, usage)
    }

    func refreshLive() async {
        guard let api else {
            if case .disabled = connection {} else { connection = .offline("Hub not configured") }
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            async let active = api.activeSessionIDs()
            async let recent = api.sessions(limit: 60)
            async let projectList = api.projects()
            let (activeKeys, recentSessions, projectsValue) = try await (active, recent, projectList)

            let newActiveIDs = Set(activeKeys)
            var merged = recentSessions
            let present = Set(recentSessions.map(\.id))
            let missing = activeKeys.filter { !present.contains($0) }
            if !missing.isEmpty {
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
            let newProjects = Dictionary(projectsValue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            if newActiveIDs != activeIDs { activeIDs = newActiveIDs }
            if newSessions != sessions { sessions = newSessions }
            if newProjects != projects { projects = newProjects }
            pruneActivity()
            rebuildDerived()
            syncSubagentLists(with: newSessions)
            connection = .connected(version: displayVersion)
            hubError = nil
            lastUpdated = Date()
        } catch {
            let text = message(for: error)
            hubError = text
            connection = .offline(text)
        }

        seedActivities()
    }

    func refreshStats(force: Bool = false) async {
        guard let api else { return }
        if !force, let fetched = statsFetchedAt, Date().timeIntervalSince(fetched) < 30 { return }
        do {
            let fresh = try await api.stats()
            stats = fresh
            statsFetchedAt = Date()
            statsStale = false
        } catch {
            if stats != nil { statsStale = true }
        }
    }

    func refreshHistory(force: Bool = false) async {
        guard let api else { return }
        if !force, let fetched = historyFetchedAt, Date().timeIntervalSince(fetched) < 60 { return }
        do {
            history = SessionOrdering.mostRecentFirst(try await api.sessions(limit: 1_000))
            historyFetchedAt = Date()
        } catch {
            // Keep the previous history; charts still render.
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

    // MARK: - Events

    private func startEvents(location: HubLocation) {
        eventTask?.cancel()
        eventTask = HubEventStream.connect(baseURL: location.url, token: location.token) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    private func handle(_ event: OpenCodeEvent) {
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

    private func scheduleLiveRefresh() {
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

    private func applyUsage(_ data: OpenCodeEvent.Payload?, to id: String) {
        guard let data, let cost = data.cost, let tokens = data.tokens else { return }
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].cost = cost
            sessions[index].tokens = tokens
            updateDerivedSession(sessions[index])
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

    private func pruneActivity() {
        let cutoff = Date().addingTimeInterval(-10)
        liveActivity = liveActivity.filter { id, activity in
            activeIDs.contains(id) || activity.updatedAt > cutoff
        }
        seedAttempts = seedAttempts.filter { activeIDs.contains($0.key) }
    }

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
                if let existing = self.liveActivity[id], existing.updatedAt > derived.updatedAt { return }
                self.liveActivity[id] = derived
            }
        }
    }

    // MARK: - Detail data

    /// Keeps the on-demand caches bounded so opening many sessions or projects
    /// does not keep every message, patch and file list alive.
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

    func messages(
        for sessionID: String,
        limit: Int = 100,
        cursor: String? = nil
    ) async throws -> SessionMessagesResponse {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        return try await api.sessionMessages(id: sessionID, limit: limit, cursor: cursor)
    }

    /// Creates a session in a project directory. The caller decides when to
    /// navigate to it, since the mobile app owns its navigation path.
    func createSession(title: String?, directory: String) async throws -> Session {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        let session = try await api.createSession(title: title, directory: directory)
        sessions.insert(session, at: 0)
        rebuildDerived()
        await refreshLive()
        return session
    }

    /// Sends a prompt into an existing session. Running sessions queue the
    /// message by default so it does not interrupt the current turn.
    func promptSession(
        id: String,
        text: String,
        delivery: PromptDelivery? = nil
    ) async throws {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        try await api.promptSession(id: id, text: text, delivery: delivery)
        activeIDs.insert(id)
        rebuildDerived()
        await refreshLive()
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
            detail.error = message(for: error)
            projectDetails[id] = detail
        }
    }

    /// Loads the file patches written by one session. The hub hydrates message
    /// history on demand, so the first request can page through a long session.
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
            sessionChanges[sessionID] = ChangesState(
                changes: changes,
                loadedAt: Date()
            )
        } catch {
            var failed = sessionChanges[sessionID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                sessionChanges[sessionID] = failed
                return
            }
            failed.error = message(for: error)
            sessionChanges[sessionID] = failed
        }
    }

    /// Loads a session's prompts, tool reliability, failures and file totals.
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
            failed.error = message(for: error)
            sessionStats[sessionID] = failed
        }
    }

    /// Loads changes across a project's newest sessions.
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
            projectChanges[projectID] = ChangesState(
                changes: changes,
                loadedAt: Date()
            )
        } catch {
            var failed = projectChanges[projectID] ?? ChangesState()
            failed.isLoading = false
            if Task.isCancelled {
                projectChanges[projectID] = failed
                return
            }
            failed.error = message(for: error)
            projectChanges[projectID] = failed
        }
    }

    /// Loads every file in a project folder, with git working-tree status.
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
            failed.error = message(for: error)
            projectFiles[projectID] = failed
        }
    }

    func loadSubagents(_ parentID: String, force: Bool = false) async {
        guard let api else { return }
        if subagentLists[parentID]?.isLoading == true { return }
        if !force, let loaded = subagentLists[parentID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&subagentLists, loadedAt: { $0.loadedAt }, pinning: parentID) }

        var list = subagentLists[parentID] ?? SubagentList()
        list.isLoading = true
        list.error = nil
        subagentLists[parentID] = list

        do {
            let children = try await api.sessions(parentID: parentID, limit: 50)
            subagentLists[parentID] = SubagentList(
                sessions: SubagentOrdering.sorted(children, activeIDs: activeIDs),
                loadedAt: Date()
            )
        } catch {
            var failed = subagentLists[parentID] ?? SubagentList()
            failed.isLoading = false
            if Task.isCancelled {
                subagentLists[parentID] = failed
                return
            }
            failed.error = message(for: error)
            subagentLists[parentID] = failed
        }
    }

    func subagentList(for parentID: String) -> SubagentList? {
        subagentLists[parentID]
    }

    func hasSubagents(_ parentID: String) -> Bool {
        !(subagentLists[parentID]?.sessions.isEmpty ?? true)
    }

    func isLoadingSubagents(_ parentID: String) -> Bool {
        subagentLists[parentID]?.isLoading == true
    }

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

    func activity(for sessionID: String) -> SessionActivity? {
        liveActivity[sessionID]
    }

    func isRunning(_ session: Session) -> Bool {
        activeIDs.contains(session.id)
    }

    func session(id: String) -> Session? {
        if let match = sessions.first(where: { $0.id == id }) { return match }
        for list in subagentLists.values {
            if let match = list.sessions.first(where: { $0.id == id }) { return match }
        }
        for detail in projectDetails.values {
            if let match = detail.sessions.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    var activeCount: Int { activeIDs.count }

    /// True until the first poll has produced anything to show.
    var isInitialLoading: Bool {
        lastUpdated == nil && sessions.isEmpty && stats == nil
    }

    /// Rebuilds the feeds the views read. Called after the session list,
    /// running set or project map changes, so filtering and sorting happen once
    /// per refresh rather than on every view body evaluation.
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
    /// move on an event, without rebuilding the whole list.
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

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
