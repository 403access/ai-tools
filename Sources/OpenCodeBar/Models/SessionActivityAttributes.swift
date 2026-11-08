#if os(iOS)
import ActivityKit
import Foundation

/// Payload shared by the iOS app (which starts and updates the activity) and
/// the widget extension (which renders it).
///
/// The activity follows one session for its whole lifetime. Keeping the
/// session id in the attributes rather than the content stops the card from
/// jumping between sessions that take turns updating and would otherwise both
/// look like "the newest".
struct SessionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var project: String
        var activity: String?
        var activityDetail: String?
        var activityIcon: String?
        var startedAt: Date
        /// Completed fraction of the session's todo list, when it has one.
        var progress: Double?
        /// Sessions running in total, including the one this card follows.
        var runningCount: Int
        var cost: Double
        var tokens: Double
        /// False while the app cannot reach the hub. The card stays useful and
        /// the timer keeps ticking; only new activity lines stop arriving.
        var hubConnected: Bool
    }

    var sessionID: String
}
#endif
