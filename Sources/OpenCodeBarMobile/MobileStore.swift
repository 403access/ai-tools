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
    @Published var sessionStats: [String: SessionStatsState] = [:]
    @Published var subagentLists: [String: SubagentList] = [:]
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    @Published var hubError: String?

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

    init(settings: HubSettingsStore) {
        self.settingsStore = settings
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

        guard let location = settingsStore.settings.location else {
            connection = .disabled
            return
        }

        connection = .connecting
        api = HubAPI(location: location)
        startEvents(location: location)
        Task { await bootstrap() }

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
                await self?.refreshUsage()
            }
        }
    }

    func stop() {
        started = false
        liveTask?.cancel()
        slowTask?.cancel()
        eventTask?.cancel()
        debounceTask?.cancel()
        liveTask = nil
        slowTask = nil
        eventTask = nil
        debounceTask = nil
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
        sessionStats = [:]
        subagentLists = [:]
        lastUpdated = nil
        statsFetchedAt = nil
        historyFetchedAt = nil
        hubError = nil
        eventStreamConnected = false
        seedAttempts = [:]
        seeding = []
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
        await refreshLive()
        await refreshStats(force: true)
        await refreshHistory(force: true)
        await refreshUsage()
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

            activeIDs = Set(activeKeys)
            pruneActivity()

            var merged = recentSessions
            let present = Set(recentSessions.map(\.id))
            for id in activeKeys where !present.contains(id) {
                if let session = try? await api.session(id: id) {
                    merged.insert(session, at: 0)
                }
            }

            sessions = merged
            syncSubagentLists(with: merged)
            projects = Dictionary(projectsValue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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
            history = try await api.sessions(limit: 1_000)
            historyFetchedAt = Date()
        } catch {
            // Keep the previous history; charts still render.
        }
    }

    func refreshUsage() async {
        guard let api else { return }
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
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshLive()
        }
    }

    private func applyUsage(_ data: OpenCodeEvent.Payload?, to id: String) {
        guard let data, let cost = data.cost, let tokens = data.tokens else { return }
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].cost = cost
            sessions[index].tokens = tokens
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
        await refreshLive()
    }

    func loadProject(_ id: String, force: Bool = false) async {
        guard let api else { return }
        if !force, projectDetails[id]?.isLoading == true { return }
        if !force, let detail = projectDetails[id], let loaded = detail.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }

        projectDetails[id, default: ProjectDetail()].isLoading = true
        do {
            async let stats = api.stats(project: id)
            async let sessions = api.sessions(projectID: id, limit: 1_000)
            let (scopedStats, recent) = try await (stats, sessions)
            projectDetails[id] = ProjectDetail(stats: scopedStats, sessions: recent, loadedAt: Date())
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

    func loadSubagents(_ parentID: String, force: Bool = false) async {
        guard let api else { return }
        if subagentLists[parentID]?.isLoading == true { return }
        if !force, let loaded = subagentLists[parentID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }

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

    var runningSessions: [Session] {
        sessions
            .filter { activeIDs.contains($0.id) }
            .sorted { $0.time.updated > $1.time.updated }
    }

    var recentSessions: [Session] {
        sessions
            .filter { !activeIDs.contains($0.id) }
            .sorted { $0.time.updated > $1.time.updated }
    }

    /// Projects with running work first, then most recently active. Duplicate
    /// records for the same directory are merged, matching the Mac app.
    var orderedProjects: [Project] {
        Dictionary(grouping: projects.values, by: \.canonical)
            .values
            .compactMap { records in records.max(by: ranksBelow) }
            .sorted { ranksBelow($1, than: $0) }
    }

    private func ranksBelow(_ lhs: Project, than rhs: Project) -> Bool {
        let left = runningSessions(in: lhs).count
        let right = runningSessions(in: rhs).count
        if left != right { return left < right }
        let leftVCS = lhs.vcs?.isEmpty == false
        let rightVCS = rhs.vcs?.isEmpty == false
        if leftVCS != rightVCS { return !leftVCS }
        return lhs.lastActiveDate < rhs.lastActiveDate
    }

    func runningSessions(in project: Project) -> [Session] {
        sessions
            .filter { $0.projectID == project.id && activeIDs.contains($0.id) }
            .sorted { $0.time.updated > $1.time.updated }
    }

    func sessions(in project: Project) -> [Session] {
        sessions.filter { $0.projectID == project.id }
    }

    func activeSubagentCount(for sessionID: String) -> Int {
        sessions.reduce(0) { count, session in
            count + (session.parentID == sessionID && activeIDs.contains(session.id) ? 1 : 0)
        }
    }

    func projectName(for session: Session) -> String {
        Fmt.projectName(for: session, projects: projects)
    }

    var todaySteps: Int {
        stats?.steps(onDay: Fmt.dayString(Date())) ?? 0
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
