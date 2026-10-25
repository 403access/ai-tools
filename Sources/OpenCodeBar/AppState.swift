import AppKit
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
        case system = "System"
        case settings = "Settings"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .usage: return "chart.bar.xaxis"
            case .projects: return "folder"
            case .system: return "cpu"
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

    /// Sections available in the project detail view.
    enum ProjectDetailMode: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case stats = "Stats"
        case changes = "Changes"
        case files = "Files"
        case sessions = "Sessions"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "rectangle.grid.2x2"
            case .stats: return "chart.bar.xaxis"
            case .changes: return "plus.forwardslash.minus"
            case .files: return "doc.text"
            case .sessions: return "bubble.left.and.bubble.right"
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
    /// The project's own app icon, discovered by the hub. Missing entries fall
    /// back to a folder glyph in the views.
    @Published var projectIcons: [String: NSImage] = [:]
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
    /// Prompts admitted but not yet delivered, shown above the composer.
    @Published var sessionPending: [String: PendingState] = [:]
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
    /// Full snapshot of the machine running the hub, shown on the System tab.
    @Published var systemInfo: SystemInfo?
    @Published var systemInfoFetchedAt: Date?
    @Published var systemInfoError: String?
    @Published var isRefreshingSystemInfo = false
    /// Interactive shells running on the hub host, including OpenCode's own
    /// terminal sessions.
    @Published var terminals: [SystemTerminal] = []
    @Published var terminalsFetchedAt: Date?
    @Published var terminalsError: String?
    @Published var isRefreshingTerminals = false
    @Published var isCreatingTerminal = false
    /// Tabs currently open in Terminal.app on the hub host.
    @Published var hostTerminals: [HostTerminal] = []
    @Published var hostTerminalsFetchedAt: Date?
    @Published var hostTerminalsError: String?
    @Published var isRefreshingHostTerminals = false
    @Published var isControllingMedia = false
    @Published var mediaControlError: String?
    /// Tunable hub behaviour, such as the event-stream throttle.
    @Published var serverSettings: ServerSettings?
    @Published var settingsError: String?
    @Published var settingsNotice: String?
    @Published var isRefreshingSettings = false
    @Published var isUpdatingSettings = false
    @Published var isSyncing = false
    @Published var isRestartingServer = false
    @Published var settingsUpdatedAt: Date?
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false
    /// Derived feeds, rebuilt once per refresh instead of being filtered and
    /// sorted every time a view reads them.
    @Published var runningSessions: [Session] = []
    @Published var recentSessions: [Session] = []
    @Published var orderedProjects: [Project] = []
    var runningByProject: [String: [Session]] = [:]
    var subagentCounts: [String: Int] = [:]
    var projectNames: [String: String] = [:]
    /// Session whose detail view is open, if any. Kept in sync with the
    /// session list so a running session's header keeps updating.
    @Published var selectedSession: Session?
    /// Sessions above the current one when drilling into subagents. The last
    /// element is the back destination.
    var sessionStack: [Session] = []
    /// Project whose detail page is open, if any. Kept in sync with the project
    /// list. A session opened from the project detail page leaves this set, so
    /// closing the session returns to the project.
    @Published var selectedProject: Project?
    /// Device whose detail page is open from Settings → Devices.
    @Published var selectedDevice: ConnectedDevice?
    /// Folder the host file browser is open at. Non-nil takes over the panel,
    /// so Back returns to the System tab.
    @Published var fileBrowserPath: String?
    /// Section the detail view opens on. Overridable from the command line for
    /// previews/screenshots (`--detail-mode prompts`).
    var detailMode: DetailMode = .conversation
    /// Section the project detail view opens on. Kept while a session opened
    /// from the project is on screen, so Back returns to the same tab.
    var projectMode: ProjectDetailMode = .overview

    /// Whether OpenCodeBar also runs as a desktop app. The menu bar item is
    /// always available; this controls the extra resizable window and the Dock
    /// icon that comes with it. Closing the window clears it again.
    @Published var usesDesktopWindow: Bool {
        didSet {
            guard oldValue != usesDesktopWindow else { return }
            UserDefaults.standard.set(usesDesktopWindow, forKey: Self.desktopWindowDefaultsKey)
        }
    }

    static let desktopWindowDefaultsKey = "OpenCodeBarUsesDesktopWindow"

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
    func pairingHubURL(fallingBackTo fallback: URL) -> URL {
        guard isLoopback(fallback) else { return fallback }
        // A running `make hub-tunnel` URL works from cellular, where the Mac's
        // LAN address is unreachable.
        if let tunnel = HubDiscovery.activeTunnelURL() { return tunnel }
        let lan = hubInfo?.urls?.compactMap(URL.init(string:)).first { !isLoopback($0) }
        return lan ?? fallback
    }

    func isLoopback(_ url: URL) -> Bool {
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

    @Published var statsFetchedAt: Date?

    var api: HubAPI?
    var location: HubLocation?
    var cache = UsageCache()
    var eventTask: Task<Void, Never>?
    var pollTask: Task<Void, Never>?
    var statsTask: Task<Void, Never>?
    var usageTask: Task<Void, Never>?
    var debounceTask: Task<Void, Never>?
    var discovering = false
    var started = false
    var isRefreshingUsage = false
    var historyFetchedAt: Date?
    /// Sessions whose activity is currently being seeded from messages.
    var seeding: Set<String> = []
    /// Last seed attempt per session, so a failed or empty fetch is not retried
    /// on every five-second poll.
    var seedAttempts: [String: Date] = [:]
    /// Last icon fetch per project. Icons are static enough that a missing
    /// result is not retried on every refresh.
    var projectIconAttempts: [String: Date] = [:]
    /// Whether the event stream has connected at least once. The first
    /// connection is not a reconnect, so there is no missed history to recover.
    var eventStreamConnected = false

    init() {
        usesDesktopWindow = UserDefaults.standard.bool(forKey: Self.desktopWindowDefaultsKey)
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

    func bootstrap() async {
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

    func discover() async -> HubLocation? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: HubDiscovery.load())
            }
        }
    }

    func startEvents() {
        guard let location, eventTask == nil else { return }
        eventTask = HubEventStream.connect(
            baseURL: location.url,
            token: location.token
        ) { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

}
