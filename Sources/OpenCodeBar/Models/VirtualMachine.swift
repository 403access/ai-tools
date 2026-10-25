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

enum VMSetupStep: String, CaseIterable, Identifiable, Equatable {
    case nix
    case helper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nix: return "Install Nix"
        case .helper: return "Build VM helper"
        }
    }

    var command: String {
        switch self {
        case .nix: return "curl -fsSL https://nixos.org/nix/install | sh -s -- --yes"
        case .helper: return "make vz-helper"
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
    var autostart: Bool?
}

struct VMUpdateRequest: Encodable {
    var name: String?
    var cpuCount: Int?
    var memoryMB: Int?
    var packages: [String]?
}

struct VMControlRequest: Encodable {
    var force: Bool?
}
