import Foundation

/// A snapshot of the machine running the hub. Mirrors `SystemInfo` in
/// `server/src/types.ts`; every collector is optional because support differs
/// by platform. Byte counts are bytes and durations are seconds.
struct SystemInfo: Decodable, Equatable, Sendable {
    var generatedAt: Double
    var platform: String
    var platformName: String
    var host: SystemHost
    var hub: SystemHub
    var cpu: SystemCPU
    var memory: SystemMemory
    var disks: [SystemDisk]
    var network: SystemNetwork
    var processes: SystemProcesses
    var battery: SystemBattery?
    var thermal: SystemThermal?
    var security: SystemSecurity?
    var apps: [SystemApp]
    var homebrew: SystemHomebrew?
    var runtimes: [SystemRuntime]
    var displays: [SystemDisplayGroup]
    var listeningPorts: [SystemPort]
    var docker: SystemDocker?
    var media: [SystemMedia]
    var audio: SystemAudio?
    var notes: [String]

    var generatedDate: Date {
        Date(timeIntervalSince1970: generatedAt / 1_000)
    }
}

struct SystemHost: Decodable, Equatable, Sendable {
    var name: String
    var hostname: String
    var platform: String
    var platformName: String
    var osName: String?
    var osVersion: String?
    var osBuild: String?
    var kernel: String
    var arch: String
    var machine: String?
    var model: String?
    var chip: String?
    var username: String?
    var home: String?
    var shell: String?
    var timezone: String?
    var locale: String?
    var uptime: Int
    var bootedAt: Double?
    var isVirtualMachine: Bool?
    var virtualization: String?

    var bootedDate: Date? {
        bootedAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
    }
}

struct SystemHub: Decodable, Equatable, Sendable {
    var version: String
    var pid: Int
    var runtime: String
    var runtimeVersion: String
    var startedAt: Double
    var uptime: Int
    var port: Int?
    var dbPath: String?
    var dbSizeBytes: Int64?
    var cwd: String?
    var execPath: String?
    var memoryBytes: Int64?
    var rssBytes: Int64?
    var heapUsedBytes: Int64?

    var startedDate: Date {
        Date(timeIntervalSince1970: startedAt / 1_000)
    }
}

struct SystemCPU: Decodable, Equatable, Sendable {
    var model: String?
    var vendor: String?
    var architecture: String
    var physicalCores: Int?
    var logicalCores: Int
    var speedMHz: Int?
    var usagePercent: Double?
    var perCoreUsage: [Double]?
    var loadAverage: [Double]?
    var temperatureC: Double?
}

struct SystemMemory: Decodable, Equatable, Sendable {
    var totalBytes: Int64
    var freeBytes: Int64
    var usedBytes: Int64
    var availableBytes: Int64?
    var activeBytes: Int64?
    var inactiveBytes: Int64?
    var wiredBytes: Int64?
    var compressedBytes: Int64?
    var cachedBytes: Int64?
    var swapTotalBytes: Int64?
    var swapUsedBytes: Int64?
    var swapFreeBytes: Int64?

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

struct SystemDisk: Decodable, Equatable, Sendable, Identifiable {
    var mount: String
    var filesystem: String
    var type: String?
    var totalBytes: Int64
    var usedBytes: Int64
    var freeBytes: Int64
    var readOnly: Bool?
    var removable: Bool?

    var id: String { mount }
    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

struct SystemNetworkAddress: Decodable, Equatable, Sendable {
    var address: String
    var family: String
    var internal_: Bool
    var mac: String?
    var netmask: String?
    var cidr: String?

    enum CodingKeys: String, CodingKey {
        case address, family, mac, netmask, cidr
        case internal_ = "internal"
    }
}

struct SystemNetworkInterface: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var addresses: [SystemNetworkAddress]

    var id: String { name }
}

struct SystemNetwork: Decodable, Equatable, Sendable {
    var hostname: String
    var interfaces: [SystemNetworkInterface]
    var defaultGateway: String?
    var defaultInterface: String?
    var dnsServers: [String]
}

struct SystemProcess: Decodable, Equatable, Sendable, Identifiable {
    var pid: Int
    var name: String
    var command: String?
    var user: String?
    var cpuPercent: Double?
    var memoryPercent: Double?
    var memoryBytes: Int64?

    var id: Int { pid }
}

struct SystemProcesses: Decodable, Equatable, Sendable {
    var total: Int
    var topCPU: [SystemProcess]
    var topMemory: [SystemProcess]
}

struct SystemBattery: Decodable, Equatable, Sendable {
    var present: Bool
    var percent: Int?
    var charging: Bool?
    var state: String?
    var minutesRemaining: Int?
    var cycleCount: Int?
    var condition: String?
    var healthPercent: Double?
    var temperatureC: Double?
}

struct SystemThermal: Decodable, Equatable, Sendable {
    var cpuSpeedLimitPercent: Int?
    var cpuSchedulerLimitPercent: Int?
    var pressure: String?
    var temperatureC: Double?
    var sensors: [SystemThermalSensor]?
}

struct SystemThermalSensor: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var temperatureC: Double

    var id: String { name }
}

struct SystemSecurity: Decodable, Equatable, Sendable {
    var systemIntegrityProtection: SystemFlag?
    var fileVault: SystemFlag?
    var firewall: SystemFlag?
    var gatekeeper: SystemFlag?
    var secureBoot: SystemFlag?
    var selinux: String?
    var appArmor: String?
    var defender: String?
}

/// Collector flags are heterogeneous on the wire (`true`, `false`, "On", …).
/// Decode anything into a comparable value instead of failing the whole
/// snapshot when a platform reports a string.
enum SystemFlag: Decodable, Equatable, Sendable {
    case enabled
    case disabled
    case text(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = value ? .enabled : .disabled
            return
        }
        let value = (try? container.decode(String.self)) ?? ""
        let lower = value.lowercased()
        if lower == "on" || lower == "yes" || lower == "1" ||
            lower.contains("enabled") || lower.contains(" on") || lower.contains("active") {
            self = .enabled
        } else if lower == "off" || lower == "no" || lower == "0" ||
            lower.contains("disabled") || lower.contains(" off") || lower.contains("inactive") {
            self = .disabled
        } else {
            self = .text(value)
        }
    }

    var isEnabled: Bool? {
        switch self {
        case .enabled: return true
        case .disabled: return false
        case .text: return nil
        }
    }

    var label: String {
        switch self {
        case .enabled: return "Enabled"
        case .disabled: return "Disabled"
        case .text(let value): return value.isEmpty ? "Unknown" : value
        }
    }
}

struct SystemApp: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var path: String
    var version: String?
    var bundleID: String?
    var source: String?
    var architecture: String?
    var lastModified: String?
    /// Whether the hub found artwork that clients can fetch for this app.
    var hasIcon: Bool?

    var id: String { path.isEmpty ? name : path }
}

struct SystemBrewPackage: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var version: String
    var kind: String
    var outdated: Bool

    var id: String { "\(kind)-\(name)" }
    var isCask: Bool { kind == "cask" }
}

// MARK: - App detail

/// Detailed inventory for one installed application. Mirrors `SystemAppDetail`
/// in `server/src/types.ts`.
struct SystemAppDetail: Decodable, Equatable, Sendable {
    var app: SystemApp
    var info: SystemAppInfo
    /// Present for apps the hub knows how to inspect further, such as Xcode.
    var xcode: SystemXcodeDetail?
    var generatedAt: Double

    var generatedDate: Date {
        Date(timeIntervalSince1970: generatedAt / 1_000)
    }
}

struct SystemAppInfo: Decodable, Equatable, Sendable {
    var displayName: String?
    var bundleID: String?
    var version: String?
    var build: String?
    var minimumOS: String?
    var copyright: String?
    var executable: String?
    var sizeBytes: Int64?
    var urlSchemes: [String]?
    var documentTypes: [String]?
    var extensions: [SystemAppExtension]
    var signing: SystemAppSigning?
}

struct SystemAppExtension: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var path: String
    var kind: String
    var bundleID: String?
    var version: String?

    var id: String { path }
    var kindLabel: String {
        switch kind {
        case "xpc": return "XPC service"
        case "login-item": return "Login item"
        default: return "App extension"
        }
    }
}

struct SystemAppSigning: Decodable, Equatable, Sendable {
    var authority: String?
    var identifier: String?
    var teamID: String?
    var verified: Bool
}

struct SystemXcodeDetail: Decodable, Equatable, Sendable {
    var developerDir: String?
    var version: String?
    var error: String?
    var simulators: [SystemSimulatorRuntime]
    var sdks: [SystemXcodeSDK]
    var frameworks: [SystemXcodeFramework]

    var devices: [SystemSimulatorDevice] {
        simulators.flatMap(\.devices)
    }

    var bootedCount: Int {
        devices.filter(\.isBooted).count
    }
}

struct SystemSimulatorRuntime: Decodable, Equatable, Sendable, Identifiable {
    var identifier: String
    var name: String
    var platform: String
    var version: String
    var build: String?
    var available: Bool
    var devices: [SystemSimulatorDevice]

    var id: String { identifier }
    var bootedCount: Int { devices.filter(\.isBooted).count }
}

struct SystemSimulatorDevice: Decodable, Equatable, Sendable, Identifiable {
    var udid: String
    var name: String
    var state: String
    var available: Bool
    var deviceType: String?
    var dataPath: String?
    var dataSizeBytes: Int64?
    var lastUsedAt: String?

    var id: String { udid }
    var isBooted: Bool { state.lowercased() == "booted" }
    var isShutdown: Bool { state.lowercased() == "shutdown" }
    var deviceFamily: String? {
        let raw = deviceType?.components(separatedBy: ".").last ?? ""
        return raw.isEmpty ? nil : raw.replacingOccurrences(of: "-", with: " ")
    }
}

struct SystemXcodeSDK: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var version: String?
    var platform: String?
    var canonicalName: String?
    var path: String?

    var id: String { canonicalName ?? "\(name)-\(version ?? "")" }
}

struct SystemXcodeFramework: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var path: String
    var platform: String

    var id: String { path }
}

struct SystemAppDetailEnvelope: Decodable, Sendable {
    var data: SystemAppDetail
}

struct SystemHomebrew: Decodable, Equatable, Sendable {
    var available: Bool
    var version: String?
    var prefix: String?
    var formulaCount: Int
    var caskCount: Int
    var outdatedCount: Int
    var packages: [SystemBrewPackage]
}

struct SystemRuntime: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var version: String?
    var path: String?
    var kind: String

    var id: String { name }
}

struct SystemDisplay: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var resolution: String?
    var pixels: String?
    var type: String?
    var main: Bool?
    var online: Bool?
    var mirror: Bool?

    var id: String { "\(name)-\(resolution ?? "")" }
}

struct SystemDisplayGroup: Decodable, Equatable, Sendable, Identifiable {
    var name: String
    var vendor: String?
    var model: String?
    var cores: Int?
    var displays: [SystemDisplay]

    var id: String { name }
}

struct SystemPort: Decodable, Equatable, Sendable, Identifiable {
    var port: Int
    var `protocol`: String
    var address: String?
    var process: String?
    var pid: Int?

    var id: String { "\(self.protocol)-\(address ?? "")-\(port)-\(pid ?? 0)" }
}

struct SystemContainer: Decodable, Equatable, Sendable, Identifiable {
    var id: String
    var name: String
    var image: String
    var state: String
    var status: String
    var ports: String?
    var created: String?
}

struct SystemDocker: Decodable, Equatable, Sendable {
    var available: Bool
    var version: String?
    var running: Int
    var containers: [SystemContainer]
}

/// A media session on the hub host, including the app that owns it.
struct SystemMedia: Decodable, Equatable, Sendable, Identifiable {
    var app: String
    var bundleID: String?
    var title: String?
    var artist: String?
    var album: String?
    var state: String?
    var elapsedSeconds: Double?
    var durationSeconds: Double?
    var playbackRate: Double?
    var kind: String?
    var source: String?
    var supportedCommands: [Int]?

    var id: String {
        "\(app)-\(title ?? "")-\(kind ?? "")-\(bundleID ?? "")"
    }

    var isPlaying: Bool { state?.lowercased() == "playing" }
    var isPaused: Bool { state?.lowercased() == "paused" }

    private func supports(_ command: Int) -> Bool {
        supportedCommands?.contains(command) ?? false
    }

    var supportsToggle: Bool { supports(2) || supports(0) || supports(1) }
    var supportsNext: Bool { supports(4) }
    var supportsPrevious: Bool { supports(5) }
    var supportsSkipBack: Bool { supports(12) }
    var supportsSkipForward: Bool { supports(13) }
    var canControl: Bool {
        source != "assertion"
            && (supportsToggle || supportsNext || supportsPrevious || supportsSkipBack || supportsSkipForward)
    }

    var progress: Double? {
        guard let elapsedSeconds, let durationSeconds, durationSeconds > 0 else { return nil }
        return min(1, max(0, elapsedSeconds / durationSeconds))
    }

    var stateLabel: String {
        if isPlaying { return "Playing" }
        if isPaused { return "Paused" }
        return state?.capitalized ?? "Active"
    }

    var kindIcon: String {
        if kind == "video" { return "play.rectangle.fill" }
        if kind == "audio" { return "waveform" }
        if title == nil { return "speaker.wave.2.fill" }
        return "music.note"
    }
}

struct SystemAudio: Decodable, Equatable, Sendable {
    var volumePercent: Int?
    var muted: Bool?
    var controllable: Bool

    var volumeFraction: Double {
        min(1, max(0, Double(volumePercent ?? 0) / 100))
    }
}

struct MediaControlResult: Decodable, Sendable {
    var media: [SystemMedia]
    var audio: SystemAudio?
}

/// Helpers shared by the Mac and iOS stores for instant media feedback. Players
/// publish state changes with a short delay, so the UI flips first and the next
/// poll reconciles the authoritative value.
enum MediaControlOptimism {
    static func apply(to info: inout SystemInfo, action: String, value: Double?) -> String? {
        switch action {
        case "toggle", "play", "pause":
            guard let index = info.media.firstIndex(where: \.canControl) else { return nil }
            let playing: Bool
            if action == "play" {
                playing = true
            } else if action == "pause" {
                playing = false
            } else {
                playing = !info.media[index].isPlaying
            }
            info.media[index].state = playing ? "playing" : "paused"
            info.media[index].playbackRate = playing ? 1 : 0
            return info.media[index].state
        case "volume":
            info.audio?.volumePercent = Int((value ?? 0).rounded())
        case "mute":
            info.audio?.muted = (value ?? 0) != 0
        default:
            break
        }
        return nil
    }

    static func reconcile(_ info: inout SystemInfo, expectedState: String?) {
        guard let expectedState,
              let index = info.media.firstIndex(where: \.canControl),
              info.media[index].state != expectedState
        else { return }
        info.media[index].state = expectedState
        info.media[index].playbackRate = expectedState == "playing" ? 1 : 0
    }
}

struct SystemInfoEnvelope: Decodable, Sendable {
    var data: SystemInfo
}

struct MediaControlEnvelope: Decodable, Sendable {
    var data: MediaControlResult
}
