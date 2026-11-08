import ActivityKit
import Foundation

/// Drives the large Lock Screen Live Activity for the session being tracked.
///
/// Only one activity is alive at a time. It sticks to the session it started
/// with so alternating tool calls cannot make the card jump between sessions.
/// Updates are local: they arrive while the app is running or briefly in the
/// background. Once iOS suspends the app, the card keeps its last state and the
/// system timer keeps ticking. Remote updates would need hub-sent APNs pushes;
/// see the "Live Activity push updates" item in NOTES.md.
@MainActor
final class SessionLiveActivityController {
    static let shared = SessionLiveActivityController()

    private var activity: Activity<SessionActivityAttributes>?
    private var lastState: SessionActivityAttributes.ContentState?
    private var lastUpdate = Date.distantPast

    /// The live feed already refreshes at most about once a second; do not ask
    /// ActivityKit to redraw faster than that.
    private let minimumUpdateInterval: TimeInterval = 1
    /// When the app has not reached the activity for this long (for example
    /// because it was suspended or terminated), the system dims the card.
    private let staleInterval: TimeInterval = 15 * 60

    private init() {}

    // MARK: - Publishing

    func publish(from store: MobileStore, force: Bool = false) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            end()
            return
        }

        let running = store.runningSessions
        guard !running.isEmpty else {
            end()
            return
        }

        adoptExistingActivity(running: running)

        // The system ends activities after about eight hours (and drops ended
        // ones eventually). Start a fresh card instead of updating a corpse.
        if let activity, !isUsable(activity) {
            self.activity = nil
            lastState = nil
            lastUpdate = .distantPast
        }

        if let activity,
           running.contains(where: { $0.id == activity.attributes.sessionID }) {
            update(activity, state: makeState(store: store), force: force)
            return
        }

        // The tracked session finished, or this is the first one to follow.
        end()
        guard let session = running.first else { return }
        start(session: session, store: store)
    }

    /// Ends the card immediately. Used when pairing is removed or changed so a
    /// new hub never leaves a stale activity behind.
    func end() {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        lastUpdate = .distantPast
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    // MARK: - Lifecycle

    /// Adopts an activity that outlived a previous app launch. Activities
    /// survive termination, so requesting a new one without checking would
    /// stack duplicates on the Lock Screen.
    private func adoptExistingActivity(running: [Session]) {
        guard activity == nil else { return }
        let existing = Activity<SessionActivityAttributes>.activities
        guard !existing.isEmpty else { return }

        let match = existing.first { candidate in
            isUsable(candidate) && running.contains { $0.id == candidate.attributes.sessionID }
        }
        activity = match
        lastState = nil
        lastUpdate = .distantPast

        for extra in existing where extra.id != match?.id {
            Task { await extra.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func start(session: Session, store: MobileStore) {
        let attributes = SessionActivityAttributes(sessionID: session.id)
        let state = makeState(store: store)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: staleDate()),
                pushType: nil
            )
            self.activity = activity
            lastState = state
            lastUpdate = Date()
            DevLog.shared.record(
                "Started Live Activity",
                category: .app,
                detail: session.displayTitle
            )
        } catch {
            DevLog.shared.record(
                "Live Activity request failed",
                category: .app,
                level: .error,
                detail: error.localizedDescription
            )
        }
    }

    private func update(
        _ activity: Activity<SessionActivityAttributes>,
        state: SessionActivityAttributes.ContentState,
        force: Bool
    ) {
        guard force || state != lastState else { return }
        guard force || Date().timeIntervalSince(lastUpdate) >= minimumUpdateInterval else {
            // The next refresh (at most a few seconds away) will carry this.
            return
        }

        lastState = state
        lastUpdate = Date()
        let content = ActivityContent(state: state, staleDate: staleDate())
        Task { await activity.update(content) }
    }

    // MARK: - Content

    private func makeState(store: MobileStore) -> SessionActivityAttributes.ContentState {
        let runningItems = store.runningSessions.map {
            digestItem($0, store: store, isActive: true)
        }
        let recentItems = store.recentSessions
            .filter { $0.parentID == nil }
            .prefix(8)
            .map { digestItem($0, store: store, isActive: false) }

        let digest = SessionDigest.make(
            running: runningItems,
            recent: recentItems,
            maxRows: 5,
            maxGroups: 2,
            maxEntriesPerGroup: 2
        )

        let groups = digest.groups.map { group in
            SessionActivityAttributes.ContentState.Group(
                projectID: group.projectID,
                project: group.project,
                entries: group.entries.map {
                    SessionActivityAttributes.ContentState.Entry(
                        id: $0.id,
                        title: $0.title,
                        status: $0.status
                    )
                },
                hidden: group.hidden
            )
        }

        return SessionActivityAttributes.ContentState(
            groups: groups,
            hidden: digest.hidden,
            runningCount: runningItems.filter { $0.status == .running }.count,
            reviewCount: recentItems.filter { $0.status == .review }.count,
            queuedCount: recentItems.filter { $0.status == .queued }.count,
            hubConnected: store.connection.isConnected,
            theme: WidgetShared.liveActivityTheme
        )
    }

    private func digestItem(
        _ session: Session,
        store: MobileStore,
        isActive: Bool
    ) -> SessionDigest.Item {
        SessionDigest.Item(
            id: session.id,
            title: session.displayTitle,
            projectID: session.projectID,
            project: store.projectName(for: session),
            status: session.widgetStatus(isActive: isActive),
            updatedAt: session.time.updatedDate
        )
    }

    private func isUsable(_ activity: Activity<SessionActivityAttributes>) -> Bool {
        switch activity.activityState {
        case .active, .stale:
            return true
        default:
            return false
        }
    }

    private func staleDate() -> Date {
        Date().addingTimeInterval(staleInterval)
    }
}
