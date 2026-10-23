import Foundation

/// Loads the data shown by the widgets.
///
/// The app's shared snapshot is the first choice when the hub is unreachable.
/// When pairing is available the widget asks the hub directly, so Home Screen
/// widgets stay useful without opening the app first.
enum WidgetDataLoader {
    static func load() async -> WidgetSnapshot {
        let cached = WidgetShared.loadSnapshot()

        guard let settings = WidgetShared.loadHubSettings(), settings.isConfigured else {
            var snapshot = cached ?? .empty(connection: .disabled)
            snapshot.connection = .disabled
            snapshot.message = "Pair your hub in OpenCodeBar to see live sessions."
            return snapshot
        }

        do {
            let fresh = try await WidgetHub.fetch(settings, cached: cached)
            WidgetShared.saveSnapshot(fresh)
            return fresh
        } catch {
            var fallback = cached ?? .empty(connection: .offline)
            fallback.connection = .offline
            fallback.message = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            return fallback
        }
    }
}

/// Minimal read-only hub client for the widget extension.
enum WidgetHub {
    static func fetch(_ settings: HubSettings, cached: WidgetSnapshot?) async throws -> WidgetSnapshot {
        guard let location = settings.location else { throw APIError.badURL }
        let api = HubAPI(location: location)

        async let sessionsTask = api.sessions(limit: 80)
        async let activeTask: [String]? = try? api.activeSessionIDs()
        async let projectsTask: [Project]? = try? api.projects()
        async let statsTask: Stats? = try? api.stats()
        async let usageTask: HubUsageResponse? = try? api.usage()
        async let healthTask: HubHealthResponse? = try? api.health()

        let (latest, activeIDs, fetchedProjects, stats, usage, health) = try await (
            sessionsTask,
            activeTask,
            projectsTask,
            statsTask,
            usageTask,
            healthTask
        )

        let active = Set(activeIDs ?? cached?.running.map(\.id) ?? [])
        var sessions = latest
        let known = Set(sessions.map(\.id))
        let missing = active.filter { !known.contains($0) }
        if !missing.isEmpty {
            let fetched = await withTaskGroup(of: Session?.self) { group in
                for id in missing.prefix(8) {
                    group.addTask { try? await api.session(id: id) }
                }
                var result: [Session] = []
                for await session in group {
                    if let session { result.append(session) }
                }
                return result
            }
            sessions.append(contentsOf: fetched)
        }

        let projectNames = Dictionary(
            (fetchedProjects ?? []).map { ($0.id, $0.displayName) },
            uniquingKeysWith: { first, _ in first }
        )
        // Live activity lines only come from the app's event stream. Reuse them
        // briefly, but do not show what a session was doing hours ago.
        let cacheIsFresh = cached.map { Date().timeIntervalSince($0.generatedAt) < 900 } ?? false
        let activeByID = Dictionary(
            (cacheIsFresh ? cached?.running ?? [] : []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        func map(_ session: Session) -> WidgetSnapshot.Session {
            let previous = activeByID[session.id]
            return WidgetSnapshot.Session(
                id: session.id,
                title: session.displayTitle,
                project: projectNames[session.projectID]
                    ?? session.directory.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? "Unknown project",
                model: session.model?.id,
                agent: session.agent?.isEmpty == false ? session.agent : nil,
                startedAt: session.time.createdDate,
                updatedAt: session.time.updatedDate,
                cost: session.cost,
                tokens: session.tokens.generated,
                activity: previous?.activity,
                activityDetail: previous?.activityDetail,
                activityIcon: previous?.activityIcon,
                subagents: 0
            )
        }

        let running = sessions
            .filter { active.contains($0.id) }
            .sorted { $0.time.updated > $1.time.updated }
            .map(map)

        let recent = sessions
            .filter { !active.contains($0.id) && $0.parentID == nil }
            .sorted { $0.time.updated > $1.time.updated }
            .prefix(8)
            .map(map)

        return WidgetSnapshot(
            generatedAt: Date(),
            connection: .connected,
            message: nil,
            hubVersion: health?.opencode?.version ?? health?.hub?.version,
            activeCount: active.count,
            running: running,
            recent: Array(recent),
            metrics: stats.map(metrics(from:)) ?? cached?.metrics,
            usage: usage.map(usage(from:)) ?? cached?.usage
        )
    }

    private static func metrics(from stats: Stats) -> WidgetSnapshot.Metrics {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days: [WidgetSnapshot.Day] = (0..<14).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 13, to: today) ?? today
            let key = Fmt.dayString(date)
            return WidgetSnapshot.Day(date: key, steps: stats.steps(onDay: key))
        }

        return WidgetSnapshot.Metrics(
            todaySteps: stats.steps(onDay: Fmt.dayString(Date())),
            totalSteps: stats.steps,
            sessions: stats.sessions,
            prompts: stats.prompts,
            streak: stats.streak,
            activeDays: stats.activeDays,
            cost: stats.cost,
            generatedTokens: stats.tokens.generated,
            cacheReadTokens: stats.tokens.cache.read,
            toolCalls: stats.tools.totals?.calls ?? 0,
            subagents: stats.subagents,
            days: days
        )
    }

    private static func usage(from response: HubUsageResponse) -> WidgetSnapshot.Usage {
        let windows = response.data?.ordered.map { entry in
            WidgetSnapshot.PlanWindow(
                label: entry.label,
                used: entry.window.used,
                resetsAt: entry.window.resetDate,
                isLimited: entry.window.isLimited
            )
        } ?? []

        var note: String?
        if response.stale == true, let error = response.error, !error.isEmpty {
            note = error
        }

        return WidgetSnapshot.Usage(
            configured: response.configured,
            windows: windows,
            note: note
        )
    }
}
