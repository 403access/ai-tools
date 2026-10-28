import Combine
import Foundation
import UIKit

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

    /// App icons are best-effort artwork fetched from the hub. When the hub is
    /// offline and the UI is showing a cached snapshot, callers should skip
    /// those requests rather than queue a timeout per row. A stale snapshot is
    /// treated the same way so a just-disconnected hub does not trigger an
    /// icon burst before the connection state catches up.
    var canLoadSystemIcons: Bool {
        guard connection.isConnected, systemInfoError == nil,
              let fetched = systemInfoFetchedAt
        else { return false }
        return Date().timeIntervalSince(fetched) < 20
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

    /// Sessions forked from one conversation, fetched on demand for the fork
    /// link in the session header.
    struct ForkList: Equatable {
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

    struct PendingState: Equatable {
        var items: [SessionPending] = []
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

    struct ProjectGitState: Equatable {
        var repository: GitRepository?
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

    struct SessionGitState: Equatable {
        var git: SessionGit?
        var isLoading = false
        var error: String?
        var loadedAt: Date?
    }

    enum DetailMode: String, CaseIterable, Identifiable {
        case conversation = "Conversation"
        case stats = "Stats"
        case changes = "Changes"
        case git = "Git"
        case prompts = "Prompts"
        case subagents = "Subagents"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .conversation: return "bubble.left.and.bubble.right"
            case .stats: return "wrench.and.screwdriver"
            case .changes: return "plus.forwardslash.minus"
            case .git: return "arrow.triangle.branch"
            case .prompts: return "text.quote"
            case .subagents: return "person.2"
            }
        }
    }

    @Published var connection: Connection = .connecting
    @Published var sessions: [Session] = []
    @Published var activeIDs: Set<String> = []
    @Published var projects: [String: Project] = [:]
    /// The project's own app icon, fetched from the hub. Missing entries fall
    /// back to a folder glyph in the views.
    @Published var projectIcons: [String: UIImage] = [:]
    /// Cached project icons currently being revalidated in the background.
    @Published var refreshingProjectIcons: Set<String> = []
    @Published var stats: Stats?
    @Published var statsStale = false
    @Published var usage: HubUsageResponse?
    @Published var usageFetchedAt: Date?
    @Published var hubHealth: HubHealthResponse?
    /// Hub behaviour tuned from Settings, including the host Mac's sleep policy.
    @Published var serverSettings: ServerSettings?
    @Published var isRefreshingSettings = false
    @Published var isUpdatingSettings = false
    @Published var settingsError: String?
    /// Snapshot of the Mac running the hub, shown on the System tab.
    @Published var systemInfo: SystemInfo?
    @Published var systemInfoFetchedAt: Date?
    @Published var systemInfoError: String?
    @Published var isRefreshingSystemInfo = false
    /// Interactive shells running on the Mac, including OpenCode's terminals.
    @Published var terminals: [SystemTerminal] = []
    @Published var terminalsFetchedAt: Date?
    @Published var terminalsError: String?
    @Published var isRefreshingTerminals = false
    /// Tabs open in Terminal.app on the Mac.
    @Published var hostTerminals: [HostTerminal] = []
    @Published var hostTerminalsFetchedAt: Date?
    @Published var hostTerminalsError: String?
    @Published var isRefreshingHostTerminals = false
    @Published var isControllingMedia = false
    @Published var mediaControlError: String?
    @Published var liveActivity: [String: SessionActivity] = [:]
    @Published var projectDetails: [String: ProjectDetail] = [:]
    @Published var sessionChanges: [String: ChangesState] = [:]
    /// Prompts admitted but not yet delivered, shown above the composer.
    @Published var sessionPending: [String: PendingState] = [:]
    @Published var projectChanges: [String: ChangesState] = [:]
    @Published var projectFiles: [String: ProjectFilesState] = [:]
    @Published var projectGit: [String: ProjectGitState] = [:]
    @Published var sessionGit: [String: SessionGitState] = [:]
    @Published var sessionStats: [String: SessionStatsState] = [:]
    @Published var subagentLists: [String: SubagentList] = [:]
    /// Forks per source conversation, loaded when a session header needs the
    /// reverse relationship.
    @Published var forkLists: [String: ForkList] = [:]
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    @Published var hubError: String?
    /// Top-level sessions the hub tracks on the task board. This is separate
    /// from `sessions` because the board keeps resolved work that no longer
    /// fits in the live window.
    @Published var tasks: [Session] = []
    @Published var tasksFetchedAt: Date?
    @Published var tasksError: String?
    /// Newest over-the-air build the hub published, for the update banner.
    @Published var otaLatest: OtaArtifact?
    @Published var otaFetchedAt: Date?
    /// Build id the user dismissed, so the banner stays away until the next one.
    @Published var otaDismissedID: String?
    /// Derived feeds, rebuilt once per refresh instead of on every read.
    @Published var runningSessions: [Session] = []
    @Published var recentSessions: [Session] = []
    @Published var orderedProjects: [Project] = []
    var runningByProject: [String: [Session]] = [:]
    var subagentCounts: [String: Int] = [:]
    var projectNames: [String: String] = [:]
    /// Index used by event handling so a busy stream does not scan the whole
    /// session list twice per event.
    var sessionsByID: [String: Session] = [:]

    let settingsStore: HubSettingsStore
    let database: MobileDatabase?
    var api: HubAPI?
    var hubVersion: String?
    var cachedRevision = 0
    var liveTask: Task<Void, Never>?
    var slowTask: Task<Void, Never>?
    var eventTask: Task<Void, Never>?
    var debounceTask: Task<Void, Never>?
    var started = false
    var statsFetchedAt: Date?
    var seeding: Set<String> = []
    var seedAttempts: [String: Date] = [:]
    /// Last icon fetch per project, so a missing icon is not retried on every
    /// incremental sync.
    var projectIconAttempts: [String: Date] = [:]
    /// Last time the host snapshot was written to the on-demand cache.
    var systemInfoCacheWrittenAt: Date?
    var eventStreamConnected = false
    var isRefreshingUsage = false
    var isRefreshingHealth = false
    var isRefreshingTasks = false
    var isPaused = false

    init(settings: HubSettingsStore) {
        self.settingsStore = settings
        self.database = MobileDatabase()
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        isPaused = false
        DevLog.shared.record("OpenCodeBar started", category: .app, detail: "iPhone/iPad")

        guard let location = settingsStore.settings.location else {
            connection = .disabled
            DevLog.shared.record("No hub configured", category: .app)
            return
        }

        connection = .connecting
        api = HubAPI(location: location)

        // A cache belongs to one hub. Pairing a different server must not mix
        // its sessions into this one, so start from scratch when the URL moves.
        let hubURL = location.url.absoluteString
        if database?.matches(hubURL: hubURL) == false {
            database?.clear()
            AppIconCache.reset()
        }
        database?.setHubURL(hubURL)
        AppIconCache.persistence = database
        hydrateFromCache()
        publishWidgetSnapshot(force: true)

        startEvents(location: location)
        Task { await bootstrap() }
        startTimers()
    }

    /// The polling loops, split out so they can be paused when the app is
    /// backgrounded without tearing down the connection state.
    func startTimers() {
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
        WidgetPublisher.shared.clear()
        DevLog.shared.record("Reconnecting with saved settings", category: .app)
        stop()
        database?.clear()
        AppIconCache.reset()
        cachedRevision = 0
        sessions = []
        activeIDs = []
        projects = [:]
        stats = nil
        usage = nil
        usageFetchedAt = nil
        hubHealth = nil
        liveActivity = [:]
        projectDetails = [:]
        sessionChanges = [:]
        projectChanges = [:]
        projectFiles = [:]
        projectGit = [:]
        sessionGit = [:]
        sessionStats = [:]
        subagentLists = [:]
        forkLists = [:]
        refreshingProjectIcons = []
        lastUpdated = nil
        statsFetchedAt = nil
        hubError = nil
        tasks = []
        tasksFetchedAt = nil
        tasksError = nil
        otaLatest = nil
        otaFetchedAt = nil
        otaDismissedID = nil
        eventStreamConnected = false
        seedAttempts = [:]
        seeding = []
        runningSessions = []
        recentSessions = []
        orderedProjects = []
        runningByProject = [:]
        subagentCounts = [:]
        projectNames = [:]
        sessionsByID = [:]
        connection = .connecting
        start()
    }

    /// Stops polling and clears the connection after the user removes the hub
    /// configuration.
    func disconnect() {
        WidgetPublisher.shared.clear()
        stop()
        database?.clear()
        AppIconCache.reset()
        AppIconCache.persistence = nil
        refreshingProjectIcons = []
        cachedRevision = 0
        tasks = []
        tasksFetchedAt = nil
        tasksError = nil
        otaLatest = nil
        otaFetchedAt = nil
        connection = .disabled
        hubHealth = nil
        DevLog.shared.record("Hub configuration removed", category: .app)
    }

    func bootstrap() async {
        guard let api else { return }
        let started = Date()
        do {
            let health = try await api.health()
            hubHealth = health
            hubVersion = health.opencode?.version ?? health.hub?.version
            connection = .connected(version: displayVersion)
            hubError = nil
            DevLog.shared.record(
                "Hub connected",
                category: .app,
                detail: "\(displayVersion) · \(DevLog.durationText(Date().timeIntervalSince(started)))"
            )
        } catch {
            let message = message(for: error)
            connection = .offline(message)
            hubError = message
            DevLog.shared.record(
                "Hub unreachable",
                category: .app,
                level: .error,
                detail: message
            )
        }
        await refreshAll()
    }

    /// Restores the last snapshot before any network work, so the app opens on
    /// cached sessions and usage instead of skeletons.
    func hydrateFromCache() {
        guard let snapshot = database?.loadSnapshot() else { return }
        cachedRevision = snapshot.revision
        if !snapshot.sessions.isEmpty {
            let ordered = SessionOrdering.mostRecentFirst(snapshot.sessions)
            sessions = ordered
            let cachedTasks = snapshot.sessions.filter { $0.task != nil }
            if !cachedTasks.isEmpty { tasks = sortedTasks(cachedTasks) }
        }
        projects = Dictionary(
            snapshot.projects.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        stats = snapshot.stats
        usage = snapshot.usage
        usageFetchedAt = snapshot.usage?.fetchedDate
        lastUpdated = snapshot.lastSyncedAt
        if let cached = database?.cachedSystemInfo() {
            systemInfo = cached.info
            systemInfoFetchedAt = cached.fetchedAt
            systemInfoCacheWrittenAt = cached.fetchedAt
        }
        // Running flags are only trusted briefly; the first delta corrects them.
        if let at = snapshot.activeAt, Date().timeIntervalSince(at) < 120 {
            activeIDs = Set(snapshot.active)
        }
        rebuildDerived()
    }

    var displayVersion: String {
        hubHealth?.opencode?.version ?? hubHealth?.hub?.version ?? hubVersion ?? "hub"
    }

}
