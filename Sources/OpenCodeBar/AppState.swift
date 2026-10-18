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

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .usage: return "chart.bar.xaxis"
            }
        }
    }

    @Published var connection: Connection = .connecting
    @Published var tab: Tab = .live
    @Published var sessions: [Session] = []
    @Published var activeIDs: Set<String> = []
    @Published var projects: [String: Project] = [:]
    @Published var stats: Stats?
    @Published var lastUpdated: Date?
    @Published var isRefreshing = false

    private var api: OpenCodeAPI?
    private var location: ServiceLocation?
    private var eventTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var statsTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var discovering = false
    private var statsFetchedAt: Date?
    private var started = false

    init() {
        // Allows the preview harness to open a specific tab:
        //   OpenCodeBar --preview --tab usage
        if let index = CommandLine.arguments.firstIndex(of: "--tab"),
           index + 1 < CommandLine.arguments.count,
           let requested = Tab(rawValue: CommandLine.arguments[index + 1].capitalized) {
            tab = requested
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true

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
            }
        }
    }

    private func bootstrap() async {
        guard !discovering else { return }
        discovering = true
        defer { discovering = false }

        guard let location = await discover() else {
            connection = .offline("Service not found")
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

    func refreshStats(force: Bool = false) async {
        guard let api else { return }
        if !force, let fetched = statsFetchedAt, Date().timeIntervalSince(fetched) < 30 { return }
        do {
            stats = try await api.stats()
            statsFetchedAt = Date()
        } catch {
            // Keep the last known stats; a later refresh will recover.
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

    func projectName(for session: Session) -> String {
        Fmt.projectName(for: session, projects: projects)
    }

    var todaySteps: Int {
        stats?.steps(onDay: Fmt.dayString(Date())) ?? 0
    }
}
