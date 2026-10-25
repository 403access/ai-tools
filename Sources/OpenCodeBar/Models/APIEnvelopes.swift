import Foundation

// MARK: - API envelopes

struct SessionsResponse: Decodable {
    var data: [Session]
    var cursor: Cursor?

    struct Cursor: Decodable {
        var previous: String?
        var next: String?
    }
}

struct ActiveSessionsResponse: Decodable {
    var data: [String: ActiveState]

    struct ActiveState: Decodable {
        var type: String
    }
}

struct StatsResponse: Decodable {
    var data: Stats
}

struct SessionEnvelope: Decodable {
    var data: Session
}

struct ServerInfo: Decodable {
    var version: String?
    var pid: Int?
    var urls: [String]?
    var capabilities: Capabilities?
    var hub: HubHealthResponse.Hub?

    struct Capabilities: Decodable {
        var persistentPty: Bool?
    }
}

/// A Mac or iOS app that has connected to this hub.
struct ConnectedDevice: Decodable, Identifiable {
    var id: String
    var name: String
    var platform: String
    var appVersion: String
    /// Milliseconds since the epoch.
    var firstSeen: Double
    var lastSeen: Double
    var connected: Bool

    var lastSeenDate: Date { Date(timeIntervalSince1970: lastSeen / 1000) }
    var firstSeenDate: Date { Date(timeIntervalSince1970: firstSeen / 1000) }

    var isThisDevice: Bool { id == DeviceIdentity.id }

    /// SF Symbol that represents the platform the device reported.
    var platformIconName: String {
        switch platform.lowercased() {
        case "macos": return "desktopcomputer"
        case "ipados": return "ipad"
        case "ios": return "iphone"
        default: return "questionmark.circle"
        }
    }
}

struct DevicesResponse: Decodable {
    var data: [ConnectedDevice]
}

/// Hub behaviour the Settings tab can tune. The hub clamps values, so the
/// bounds are only used to label the controls.
struct ServerSettings: Decodable, Equatable {
    /// Coalescing window for event-stream updates; `0` forwards everything.
    var eventThrottleMs: Int
    var eventThrottleMinMs: Int?
    var eventThrottleMaxMs: Int?
    /// Whether the hub currently blocks idle sleep on the host Mac.
    var preventSleep: Bool?
    /// False when the hub runs on a platform that cannot block sleep.
    var preventSleepSupported: Bool?
}

struct ServerSettingsResponse: Decodable {
    var data: ServerSettings
}
