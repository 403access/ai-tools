import Foundation

/// Tiny deep-link router for links that widgets and other clients open in the
/// app. Pairing links are still handled by `HubSettingsStore`.
@MainActor
final class MobileRouter: ObservableObject {
    /// A session the Live tab should push once the row is available.
    @Published var requestedSessionID: String?
    @Published var requestedTab: RootView.Tab?
    /// Which half of the Host tab a deep link wants.
    @Published var requestedHostMode: HostMode?

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "opencodebar" else { return false }

        switch url.host?.lowercased() {
        case "tasks":
            requestedTab = .tasks
            return true

        case "live":
            requestedTab = .live
            return true

        case "usage":
            requestedTab = .usage
            return true

        case "remote":
            requestedHostMode = .remote
            requestedTab = .host
            return true

        case "system":
            requestedHostMode = .system
            requestedTab = .host
            return true

        case "session":
            let id = url.pathComponents
                .dropFirst()
                .joined(separator: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else { return false }
            requestedSessionID = id
            requestedTab = .live
            return true

        default:
            return false
        }
    }

    func clear() {
        requestedSessionID = nil
        requestedTab = nil
        requestedHostMode = nil
    }
}
