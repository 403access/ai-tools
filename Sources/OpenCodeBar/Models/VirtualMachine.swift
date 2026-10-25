import Foundation

/// A NixOS guest managed by the hub. Mirrors `VirtualMachine` in
/// `server/src/vms/types.ts`.
struct VirtualMachine: Decodable, Identifiable, Equatable {
    enum Status: String, Codable, CaseIterable {
        case building
        case stopped
        case starting
        case running
        case stopping
        case paused
        case error
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }

        var label: String {
            switch self {
            case .building: return "Building"
            case .stopped: return "Stopped"
            case .starting: return "Starting"
            case .running: return "Running"
            case .stopping: return "Stopping"
            case .paused: return "Paused"
            case .error: return "Error"
            case .unknown: return "Unknown"
            }
        }

        var isRunning: Bool { self == .running }
        var isBusy: Bool {
            self == .building || self == .starting || self == .stopping
        }
    }

    struct Progress: Decodable, Equatable {
        var phase: String
        var message: String
        var startedAt: Double

        var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    }

    struct SSH: Decodable, Equatable {
        var user: String
        var keyPath: String
        var publicKey: String
    }

    struct Network: Decodable, Equatable {
        var mac: String
        var ip: String?
        var reachable: Bool
    }

    struct Paths: Decodable, Equatable {
        var directory: String
        var disk: String
        var configuration: String
        var flake: String
        var serialLog: String
        var buildLog: String
        var applyLog: String
        var runtime: String
    }

    struct HostMetrics: Decodable, Equatable {
        var cpuPercent: Double?
        var rssBytes: UInt64?
        var diskBytes: UInt64?
        var diskUsedBytes: UInt64?
        var uptimeSec: Int?
    }

    struct GuestMetrics: Decodable, Equatable {
        var reachable: Bool
        var uptimeSec: Int?
        var cpuPercent: Double?
        var load1: Double?
        var load5: Double?
        var load15: Double?
        var memoryTotalBytes: UInt64?
        var memoryUsedBytes: UInt64?
        var memoryAvailableBytes: UInt64?
        var swapUsedBytes: UInt64?
        var diskTotalBytes: UInt64?
        var diskUsedBytes: UInt64?
        var diskAvailableBytes: UInt64?
        var hostname: String?
        var kernel: String?
        var generation: String?
        var error: String?

        var memoryFraction: Double? {
            guard let total = memoryTotalBytes, total > 0,
                  let used = memoryUsedBytes else { return nil }
            return Double(used) / Double(total)
        }

        var diskFraction: Double? {
            guard let total = diskTotalBytes, total > 0,
                  let used = diskUsedBytes else { return nil }
            return Double(used) / Double(total)
        }
    }

    struct Metrics: Decodable, Equatable {
        var collectedAt: Double
        var state: String?
        var host: HostMetrics?
        var guest: GuestMetrics?

        var collectedDate: Date { Date(timeIntervalSince1970: collectedAt / 1000) }
    }

    var id: String
    var name: String
    var distro: String
    var channel: String
    var stateVersion: String
    var arch: String
    var status: Status
    var createdAt: Double
    var updatedAt: Double
    var cpuCount: Int
    var memoryMB: Int
    var diskGB: Int
    var packages: [String]
    var pendingPackages: [String]
    /// True when the builder configuration changed but has not been applied.
    var pendingConfig: Bool?
    /// The click-together builder configuration. Nil on older hubs.
    var config: NixOSBuilderConfig?
    var lastError: String?
    var progress: Progress?
    var ssh: SSH
    var network: Network
    var paths: Paths
    var startedAt: Double?
    var lastBootAt: Double?
    var metrics: Metrics?

    var createdDate: Date { Date(timeIntervalSince1970: createdAt / 1000) }
    var updatedDate: Date { Date(timeIntervalSince1970: updatedAt / 1000) }
    var startedDate: Date? { startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var lastBootDate: Date? { lastBootAt.map { Date(timeIntervalSince1970: $0 / 1000) } }

    var isRunning: Bool { status == .running || status == .paused }
    var isBusy: Bool { status.isBusy }
    var hasPendingPackages: Bool { !pendingPackages.isEmpty }
    var hasPendingConfig: Bool { pendingConfig == true }
    var hasPendingChanges: Bool { hasPendingPackages || hasPendingConfig }

    /// The stored builder configuration, with a sensible fallback for hubs
    /// created before the builder existed.
    var builder: NixOSBuilderConfig { config ?? .fresh() }

    var optionCount: Int {
        builder.enabled.filter { id in
            id != "ssh" && id != "flakes" && id != "optimise"
        }.count
    }

    /// NixOS already ships the base packages; show what the user added.
    var extraPackages: [String] {
        let base: Set<String> = ["curl", "git", "htop", "vim"]
        return packages.filter { !base.contains($0) }
    }

    var sshTarget: String? {
        guard let ip = network.ip, !ip.isEmpty else { return nil }
        return "\(ssh.user)@\(ip)"
    }

    var sshCommand: String? {
        guard let target = sshTarget else { return nil }
        return "ssh -i \(paths.directory)/ssh/id_ed25519 \(target)"
    }

    var directoryLabel: String {
        (paths.directory as NSString).abbreviatingWithTildeInPath
    }
}

struct VMCapabilities: Decodable, Equatable {
    var supported: Bool
    var platform: String
    var arch: String
    var helperPath: String?
    var helperAvailable: Bool
    var helperEntitled: Bool
    var nixPath: String?
    var nixAvailable: Bool
    var nixVersion: String?
    var linuxBuilder: Bool
    var linuxBuilderDetail: String?
    var storageDir: String
    var defaultChannel: String
    var defaultCPU: Int
    var defaultMemoryMB: Int
    var maxCPU: Int
    var maxMemoryMB: Int
    var notes: [String]

    var ready: Bool {
        supported && helperAvailable && helperEntitled && nixAvailable && linuxBuilder
    }
}

// MARK: - NixOS configuration builder

struct NixOSManagedUser: Codable, Equatable, Identifiable {
    var name: String
    var description: String
    var groups: [String]
    var shell: String
    var sshKeys: [String]
    var passwordlessSudo: Bool
    var createHome: Bool

    var id: String { name }

    static func fresh(existing: [NixOSManagedUser] = []) -> NixOSManagedUser {
        let used = Set(existing.map(\.name))
        var candidate = "user"
        var index = 2
        while used.contains(candidate) {
            candidate = "user\(index)"
            index += 1
        }
        return NixOSManagedUser(
            name: candidate,
            description: "Managed user",
            groups: [],
            shell: "bash",
            sshKeys: [],
            passwordlessSudo: false,
            createHome: true
        )
    }
}

struct NixOSBuilderSettings: Codable, Equatable {
    var timezone: String
    var locale: String
    var keymap: String
    var firewall: Bool
    var passwordAuthentication: Bool
    var extraTCPPorts: [Int]
    var extraUDPPorts: [Int]

    static let standard = NixOSBuilderSettings(
        timezone: "UTC",
        locale: "en_US.UTF-8",
        keymap: "us",
        firewall: true,
        passwordAuthentication: false,
        extraTCPPorts: [],
        extraUDPPorts: []
    )
}

struct NixOSBuilderConfig: Codable, Equatable {
    var version: Int
    var preset: String?
    var enabled: [String]
    var settings: NixOSBuilderSettings
    var users: [NixOSManagedUser]
    var extraPackages: [String]
    var extraConfig: String

    static func fresh() -> NixOSBuilderConfig {
        NixOSBuilderConfig(
            version: 1,
            preset: nil,
            enabled: [],
            settings: .standard,
            users: [],
            extraPackages: [],
            extraConfig: ""
        )
    }
}

struct VMConfigCategory: Decodable, Equatable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var icon: String
    var tint: String
}

struct VMConfigOption: Decodable, Equatable, Identifiable {
    var id: String
    var category: String
    var name: String
    var summary: String
    var description: String
    var icon: String
    var tint: String
    var tags: [String]
    var badge: String?
    var packages: [String]
    var requires: [String]
    var recommends: [String]
    var conflicts: [String]
    var ports: [Int]
    var services: [String]
    var defaultOn: Bool
    var locked: Bool
    var sizeMB: Int
    var unfree: Bool
}

struct VMConfigPreset: Decodable, Equatable, Identifiable {
    var id: String
    var name: String
    var summary: String
    var icon: String
    var tint: String
    var options: [String]
    var tags: [String]
}

struct VMConfigLimits: Decodable, Equatable {
    var maxUsers: Int
    var maxExtraPackages: Int
    var maxExtraConfigBytes: Int
    var maxPorts: Int
}

struct VMConfigCatalog: Decodable, Equatable {
    var version: Int
    var categories: [VMConfigCategory]
    var options: [VMConfigOption]
    var presets: [VMConfigPreset]
    var defaults: NixOSBuilderConfig
    var recommendedPreset: String?
    var shells: [String]
    var groups: [String]
    var timezones: [String]
    var locales: [String]
    var keymaps: [String]
    var limits: VMConfigLimits

    func option(_ id: String) -> VMConfigOption? {
        options.first { $0.id == id }
    }

    func preset(_ id: String?) -> VMConfigPreset? {
        guard let id else { return nil }
        return presets.first { $0.id == id }
    }

    func category(_ id: String) -> VMConfigCategory? {
        categories.first { $0.id == id }
    }
}

struct VMConfigPreview: Decodable, Equatable {
    var configuration: String
    var flake: String
    var packages: [String]
    var services: [String]
    var ports: [Int]
    var users: [String]
    var optionCount: Int
    var added: [String]
    var warnings: [String]
    var sizeMB: Int
    var stateVersion: String

    var sizeLabel: String {
        if sizeMB >= 1_024 {
            return String(format: "%.1f GB", Double(sizeMB) / 1_024)
        }
        return "\(sizeMB) MB"
    }
}

struct VMConfigCatalogEnvelope: Decodable {
    var data: VMConfigCatalog
}

struct VMConfigPreviewEnvelope: Decodable {
    var data: VMConfigPreview
}

enum VMLogType: String, CaseIterable, Identifiable {
    case build
    case serial
    case apply

    var id: String { rawValue }

    var title: String {
        switch self {
        case .build: return "Build"
        case .serial: return "Boot"
        case .apply: return "Config"
        }
    }
}

struct VMLog: Decodable, Equatable {
    var type: String
    var path: String
    var lines: [String]
    var bytes: Int
    var truncated: Bool
}

enum VMSetupStep: String, CaseIterable, Identifiable, Equatable, Hashable {
    case nix
    case helper
    case builder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nix: return "Install Nix"
        case .helper: return "Build VM helper"
        case .builder: return "Linux builder"
        }
    }

    var command: String {
        switch self {
        case .nix: return "curl -fsSL https://nixos.org/nix/install | sh -s -- --yes"
        case .helper: return "make vz-helper"
        case .builder: return "nix --extra-experimental-features 'nix-command flakes' run nixpkgs#darwin.linux-builder"
        }
    }
}

enum VMSetupJobStatus: String, Decodable, Equatable {
    case running
    case succeeded
    case failed
    case cancelled
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VMSetupJobStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .running: return "Running"
        case .succeeded: return "Done"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        case .unknown: return "Unknown"
        }
    }
}

struct VMSetupLog: Decodable, Equatable {
    var path: String
    var lines: [String]
    var bytes: Int
    var truncated: Bool
}

struct VMSetupJob: Decodable, Equatable {
    var step: String
    var status: VMSetupJobStatus
    var command: String
    var requiresAdmin: Bool
    var startedAt: Double
    var finishedAt: Double?
    var exitCode: Int?
    var error: String?
    var log: VMSetupLog

    var startedDate: Date { Date(timeIntervalSince1970: startedAt / 1000) }
    var finishedDate: Date? { finishedAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
    var stepValue: VMSetupStep? { VMSetupStep(rawValue: step) }
}

struct VMSetupJobEnvelope: Decodable {
    var data: VMSetupJob?
}

struct VMSetupLogFile: Decodable, Equatable, Identifiable {
    var step: String
    var path: String
    var bytes: Int
    var modified: Double

    var id: String { path }
    var modifiedDate: Date { Date(timeIntervalSince1970: modified / 1000) }
}

struct VMSetupLogFilesEnvelope: Decodable {
    var data: [VMSetupLogFile]
}

struct VMSetupLogResult: Decodable, Equatable {
    var step: String
    var path: String
    var lines: [String]
    var bytes: Int
    var truncated: Bool
}

struct VMSetupLogResultEnvelope: Decodable {
    var data: VMSetupLogResult
}

struct VMSetupStartRequest: Encodable {
    var step: String
}

// MARK: - Envelopes and requests

struct VirtualMachinesEnvelope: Decodable {
    var data: [VirtualMachine]
}

struct VirtualMachineEnvelope: Decodable {
    var data: VirtualMachine
}

struct VMCapabilitiesEnvelope: Decodable {
    var data: VMCapabilities
}

struct VMLogEnvelope: Decodable {
    var data: VMLog
}

struct VMCreateRequest: Encodable {
    var name: String
    var cpuCount: Int?
    var memoryMB: Int?
    var diskGB: Int?
    var channel: String?
    var packages: [String]?
    var config: NixOSBuilderConfig?
    var autostart: Bool?
}

struct VMUpdateRequest: Encodable {
    var name: String?
    var cpuCount: Int?
    var memoryMB: Int?
    var packages: [String]?
    var config: NixOSBuilderConfig?
}

struct VMControlRequest: Encodable {
    var force: Bool?
}
