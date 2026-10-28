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

/// A repository the hub cloned for a new session.
struct ClonedRepository: Decodable, Hashable, Sendable {
    /// Absolute path of the cloned working tree on the hub host.
    var directory: String
    /// Folder name of the clone.
    var name: String
    /// Normalized repository URL passed to git.
    var url: String
}

struct CloneRepositoryResponse: Decodable {
    var data: ClonedRepository
}

/// An isolated checkout created for a new session.
struct CreatedWorktree: Decodable, Hashable, Sendable {
    /// Absolute path of the worktree on the hub host.
    var directory: String
}

struct CreateWorktreeResponse: Decodable {
    var data: CreatedWorktree
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

/// One install of an app build on a physical device. `endedAt` is absent while
/// that build is the one installed for its bundle id.
struct Deployment: Decodable, Identifiable, Equatable {
    var id: String
    var deviceKey: String
    var deviceName: String
    var deviceModel: String
    var bundleId: String
    var appName: String
    /// Variant slug for side-by-side builds; empty for the normal app.
    var variant: String
    var version: String
    var build: String
    var commitSha: String
    var branch: String
    var worktree: String
    /// `script` for an install reported by the scripts, `sync` for a scan.
    var source: String
    var installedAt: Double
    var endedAt: Double?
    var endReason: String?

    var isCurrent: Bool { endedAt == nil }
    var installedAtDate: Date { Date(timeIntervalSince1970: installedAt / 1000) }
    var endedAtDate: Date? {
        endedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var displayName: String {
        if !appName.isEmpty { return appName }
        return variant.isEmpty ? "OpenCodeBar" : "OpenCodeBar \(variant)"
    }

    /// "1.0 (1)" or whichever half the bundle reported.
    var buildLabel: String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false): return "\(version) (\(build))"
        case (false, true): return version
        case (true, false): return "build \(build)"
        case (true, true): return "unknown build"
        }
    }

    var shortCommit: String {
        commitSha.isEmpty ? "" : String(commitSha.prefix(7))
    }

    var endLabel: String? {
        switch endReason {
        case "replaced": return "Replaced"
        case "uninstalled": return "Uninstalled"
        default: return endedAt == nil ? nil : "Ended"
        }
    }
}

/// A physical iPhone/iPad and the OpenCodeBar builds installed on it now.
struct DeploymentDevice: Decodable, Identifiable, Equatable {
    var key: String
    var name: String
    var model: String
    var platform: String
    /// devicectl state: connected, unavailable, or empty before the first scan.
    var state: String
    /// True when the OpenCodeBar app on this device is live on the hub.
    var connected: Bool
    var lastSeen: Double?
    var lastSynced: Double?
    var current: [Deployment]

    var id: String { key }
    var icon: String { platform == "iPadOS" ? "ipad" : "iphone" }

    var lastSyncedDate: Date? {
        lastSynced.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    /// devicectl says "connected" only while the phone is reachable; the hub
    /// connection flag is separate (a paired phone can be asleep but online).
    var isReachable: Bool { state == "connected" }
    var stateLabel: String {
        if connected { return "App connected" }
        switch state.lowercased() {
        case "": return "Not scanned"
        case "connected": return "Reachable"
        case "available", "available (paired)": return "Paired"
        case "unavailable", "disconnected": return "Unavailable"
        default: return state.capitalized
        }
    }
}

struct DeploymentsPayload: Decodable {
    var devices: [DeploymentDevice]
    var deployments: [Deployment]
    var syncedAt: Double?
    var errors: [String]?
}

struct DeploymentsResponse: Decodable {
    var data: DeploymentsPayload
}

/// One published over-the-air build the hub serves to a phone's browser.
struct OtaArtifact: Decodable, Identifiable, Equatable {
    var id: String
    var title: String
    var bundleId: String
    var version: String
    var build: String
    var commitSha: String
    var branch: String
    var worktree: String
    var createdAt: Double

    var createdAtDate: Date { Date(timeIntervalSince1970: createdAt / 1000) }

    var buildLabel: String {
        switch (version.isEmpty, build.isEmpty) {
        case (false, false): return "\(version) (\(build))"
        case (false, true): return version
        case (true, false): return "build \(build)"
        case (true, true): return "unknown build"
        }
    }

    var shortCommit: String { commitSha.isEmpty ? "" : String(commitSha.prefix(7)) }
}

/// Progress of the single background build the hub runs at a time.
struct OtaBuildStatus: Decodable, Equatable {
    var state: String
    var startedAt: Double?
    var finishedAt: Double?
    /// Tail of the archive/export output, newest last.
    var log: [String]
    var error: String?
    var artifact: OtaArtifact?
    /// True when the run also installed the build straight onto a reachable phone.
    var installed: Bool?
    /// Name of the phone the build was installed on, when known.
    var device: String?

    var isRunning: Bool { state == "running" }
    var isFailed: Bool { state == "failed" }
    var isSucceeded: Bool { state == "succeeded" }
    var lastLogLine: String? { log.last }
}

struct OtaPayload: Decodable {
    var latest: OtaArtifact?
    var builds: [OtaArtifact]
    var build: OtaBuildStatus
}

struct OtaResponse: Decodable {
    var data: OtaPayload
}

struct OtaBuildResponse: Decodable {
    var data: OtaBuildStatus
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
    /// Agent sessions that may run at once; `0` means no limit.
    var maxConcurrentAgents: Int?
    var maxConcurrentAgentsMin: Int?
    var maxConcurrentAgentsMax: Int?
}

struct ServerSettingsResponse: Decodable {
    var data: ServerSettings
}
