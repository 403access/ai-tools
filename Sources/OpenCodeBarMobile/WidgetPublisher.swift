import Foundation
import WidgetKit

/// Mirrors the app's current state into the widget snapshot store and asks
/// WidgetKit to refresh. The widgets fetch the hub themselves, but this keeps a
/// foreground app's richer live activity line available when the App Group is
/// provisioned, and the reload nudge makes new activity show up promptly.
@MainActor
final class WidgetPublisher {
    static let shared = WidgetPublisher()

    private var lastFingerprint: Int?
    private var lastReload = Date.distantPast
    private var pendingReload: Task<Void, Never>?

    /// Widget timelines should not be reloaded more than about once a minute;
    /// the system throttles them anyway and the live feed polls often.
    private let minimumReloadInterval: TimeInterval = 60

    func publish(from store: MobileStore, force: Bool = false) {
        let snapshot = makeSnapshot(from: store)
        let fingerprint = fingerprint(of: snapshot)
        guard force || fingerprint != lastFingerprint else { return }
        lastFingerprint = fingerprint
        WidgetShared.saveSnapshot(snapshot)
        scheduleReload(force: force)
    }

    /// Called after unpairing or moving to another hub so a new pairing never
    /// shows rows from the old server.
    func clear() {
        pendingReload?.cancel()
        pendingReload = nil
        lastFingerprint = nil
        WidgetShared.clearSnapshot()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Snapshot

    private func makeSnapshot(from store: MobileStore) -> WidgetSnapshot {
        let connection: WidgetSnapshot.Connection
        var message: String?
        switch store.connection {
        case .connected:
            connection = .connected
        case .connecting:
            connection = .connecting
        case .offline(let reason):
            connection = .offline
            message = reason
        case .disabled:
            connection = .disabled
            message = "Pair the hub in OpenCodeBar to see live sessions."
        }

        let running = store.runningSessions.map { session($0, store: store) }
        let recent = store.recentSessions
            .filter { $0.parentID == nil }
            .prefix(8)
            .map { session($0, store: store) }

        return WidgetSnapshot(
            generatedAt: Date(),
            connection: connection,
            message: message,
            hubVersion: store.connection.isConnected ? store.displayVersion : nil,
            activeCount: store.activeCount,
            running: running,
            recent: Array(recent),
            metrics: store.stats.map(metrics(from:)),
            usage: store.usage.map(usage(from:))
        )
    }

    private func session(_ session: Session, store: MobileStore) -> WidgetSnapshot.Session {
        let activity = store.liveActivity[session.id]
        var headline: String?
        var detail: String?
        var icon: String?

        if let activity {
            icon = activity.icon
            if activity.phase == .tool, let tool = activity.tool {
                headline = activity.toolVerb
                detail = tool.summary
            } else {
                headline = activity.headline
                detail = activity.detailLine
            }
        }

        return WidgetSnapshot.Session(
            id: session.id,
            title: session.displayTitle,
            project: store.projectName(for: session),
            model: session.model?.id,
            agent: session.agent?.isEmpty == false ? session.agent : nil,
            startedAt: session.time.createdDate,
            updatedAt: session.time.updatedDate,
            cost: session.cost,
            tokens: session.tokens.generated,
            activity: headline,
            activityDetail: detail,
            activityIcon: icon,
            subagents: store.activeSubagentCount(for: session.id)
        )
    }

    private func metrics(from stats: Stats) -> WidgetSnapshot.Metrics {
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

    private func usage(from response: HubUsageResponse) -> WidgetSnapshot.Usage {
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

    /// The generated timestamp changes on every call, so compare everything
    /// else to avoid writing and reloading when the feed is quiet.
    private func fingerprint(of snapshot: WidgetSnapshot) -> Int {
        var probe = snapshot
        probe.generatedAt = .distantPast
        guard let data = try? JSONEncoder().encode(probe) else { return 0 }
        return data.hashValue
    }

    // MARK: - Reloads

    private func scheduleReload(force: Bool) {
        if force || Date().timeIntervalSince(lastReload) >= minimumReloadInterval {
            pendingReload?.cancel()
            pendingReload = nil
            lastReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        guard pendingReload == nil else { return }
        let delay = minimumReloadInterval - Date().timeIntervalSince(lastReload)
        pendingReload = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.pendingReload = nil
            self?.lastReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension MobileStore {
    func publishWidgetSnapshot(force: Bool = false) {
        WidgetPublisher.shared.publish(from: self, force: force)
    }
}
