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

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .usage: return "chart.bar.xaxis"
            case .projects: return "folder"
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

    /// Sections available in the session detail view.
    enum DetailMode: String, CaseIterable, Identifiable {
        case conversation = "Conversation"
        case prompts = "Prompts"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .conversation: return "bubble.left.and.bubble.right"
            case .prompts: return "text.quote"
            }
        }
    }

    @Published var connection: Connection = .connecting
    @Published var tab: Tab = .live
    @Published var sessions: [Session] = []
    @Published var activeIDs: Set<String> = []
    @Published var projects: [String: Project] = [:]
    @Published var stats: Stats?
    @Published var statsStale = false
    @Published var goUsage: GoUsageState = .unavailable
    @Published var goUsageFetchedAt: Date?
    @Published var projectDetails: [String: ProjectDetail] = [:]
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    /// Session whose detail view is open, if any. Kept in sync with the
    /// session list so a running session's header keeps updating.
    @Published var selectedSession: Session?
    /// Project whose detail page is open, if any. Kept in sync with the project
    /// list. A session opened from the project detail page leaves this set, so
    /// closing the session returns to the project.
    @Published var selectedProject: Project?
    /// Section the detail view opens on. Overridable from the command line for
    /// previews/screenshots (`--detail-mode prompts`).
    var detailMode: DetailMode = .conversation

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

    private var api: OpenCodeAPI?
    private var location: ServiceLocation?
    private var cache = UsageCache()
    private var eventTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var usageTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var discovering = false
    private var started = false

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
                await self?.refreshSelectedProject()
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
            connection = .offline("Service not found")
            if stats != nil { statsStale = true }
            return
        }
        self.location = location
        self.api = OpenCodeAPI(location: location)
        await refreshAll()
        startEvents()
    }

    private func discover() async -> ServiceLocation? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: ServiceDiscovery.load())
            }
        }
    }

    private func startEvents() {
        guard let location, eventTask == nil else { return }
        eventTask = EventStream.connect(location: location) { [weak self] in
            Task { @MainActor in self?.scheduleLiveRefresh() }
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        await refreshLive()
        await refreshStats(force: true)
        await refreshGoUsage()
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

            self.activeIDs = Set(activeIDs)
            var merged = recentSessions
            let present = Set(recentSessions.map(\.id))
            let missing = activeIDs.filter { !present.contains($0) }
            for id in missing {
                if let session = try? await api.session(id: id) {
                    merged.insert(session, at: 0)
                }
            }
            self.sessions = merged
            self.projects = Dictionary(projectListValue.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

            if let selected = selectedSession,
               let updated = merged.first(where: { $0.id == selected.id }) {
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

    /// Fetches Go plan quota. Cheap when no key is configured: `auth.json` is
    /// re-read each cycle so a new key is picked up without a restart.
    func refreshGoUsage() async {
        guard let key = GoUsageClient.apiKey() else {
            goUsage = .unavailable
            return
        }
        switch goUsage {
        case .ready, .stale:
            break // Keep showing the current numbers while refreshing.
        case .unavailable, .loading, .failed:
            goUsage = .loading
        }
        do {
            let usage = try await GoUsageClient.fetch(key: key)
            goUsage = .ready(usage)
            goUsageFetchedAt = Date()
            cache.goUsage = usage
            cache.goUsageFetchedAt = goUsageFetchedAt
            cache.save()
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
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshLive()
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

    func open(_ session: Session) {
        selectedSession = session
    }

    func closeDetail() {
        selectedSession = nil
    }

    /// Title of the session detail view's back button. Sessions opened from a
    /// project return there; everything else returns to the Live tab.
    var sessionBackTitle: String {
        selectedProject?.displayName ?? "Live"
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

    // MARK: - Projects

    /// Opens the full detail page for a project, loading its scoped stats and
    /// recent sessions on demand.
    func open(_ project: Project) {
        selectedProject = project
        Task { await loadProject(project.id) }
    }

    func closeProject() {
        selectedProject = nil
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
            async let sessions = api.sessions(projectID: id, limit: 20)
            let (scopedStats, recent) = try await (stats, sessions)
            projectDetails[id] = ProjectDetail(stats: scopedStats, sessions: recent, loadedAt: Date())
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
    }

    // MARK: - Derived data

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

    var activeCount: Int { activeIDs.count }

    /// Projects with running work first, then most recently active.
    ///
    /// OpenCode can hold more than one record for the same directory — a legacy
    /// record alongside the live one — so records are merged by canonical path,
    /// keeping whichever has activity.
    var orderedProjects: [Project] {
        Dictionary(grouping: projects.values, by: \.canonical)
            .values
            .compactMap { records in records.max(by: ranksBelow) }
            .sorted { ranksBelow($1, than: $0) } // reversed: best first
    }

    /// Ordering used both to pick a winner among duplicate records and to sort
    /// the list: running work, then real VCS projects, then recent activity.
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

    func projectName(for session: Session) -> String {
        Fmt.projectName(for: session, projects: projects)
    }

    var todaySteps: Int {
        stats?.steps(onDay: Fmt.dayString(Date())) ?? 0
    }
}
