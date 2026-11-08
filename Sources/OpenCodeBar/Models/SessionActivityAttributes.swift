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
        struct Entry: Codable, Hashable, Identifiable {
            var id: String
            var title: String
            var status: WidgetSnapshot.Session.Status
        }

        struct Group: Codable, Hashable, Identifiable {
            var projectID: String?
            var project: String
            var entries: [Entry]
            /// Sessions in this project that did not fit.
            var hidden: Int

            var id: String { projectID ?? project }
        }

        /// Sessions grouped by project, ranked the same way as the Lock Screen
        /// widget. The large card shows names and statuses only.
        var groups: [Group]
        /// Items that did not fit across all groups.
        var hidden: Int
        /// Sessions running in total, which can exceed what fits on the card.
        var runningCount: Int
        var reviewCount: Int
        var queuedCount: Int
        /// False while the app cannot reach the hub.
        var hubConnected: Bool
        /// Chosen in the app's Settings. Part of the state so changing it
        /// refreshes an activity that is already on the Lock Screen.
        var theme: LiveActivityTheme
    }

    var sessionID: String
}
#endif
