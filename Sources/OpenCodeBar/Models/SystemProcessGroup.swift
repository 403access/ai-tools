import Foundation

/// A set of related processes shown as one row when the memory monitor groups
/// helper processes under their owning application. Applications are detected
/// from the `.app` bundle embedded in the executable path (for example
/// `/Applications/Google Chrome.app/.../Google Chrome Helper`), so renderer,
/// GPU and plugin helpers roll up under "Google Chrome".
struct SystemProcessGroup: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable {
        case application
        case process
    }

    let id: String
    let name: String
    let kind: Kind
    let processes: [SystemProcess]
    let app: SystemApp?

    var processCount: Int { processes.count }
    var isApplication: Bool { kind == .application }

    var totalMemoryBytes: Int64 {
        processes.reduce(0) { $0 + ($1.memoryBytes ?? 0) }
    }

    var totalCPUPercent: Double {
        processes.reduce(0) { $0 + ($1.cpuPercent ?? 0) }
    }

    var users: [String] {
        var seen = Set<String>()
        return processes
            .compactMap(\.user)
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .sorted()
    }
}

/// Client-side grouping for the memory monitor. The hub reports a bounded
/// process list, so totals are explicitly described as "listed" in the UI.
enum SystemProcessGrouping {
    private static let bundleRegex = try? NSRegularExpression(
        pattern: #"(?i)^(.+?\.app)(?:/|$)"#
    )
    private static let helperRegex = try? NSRegularExpression(
        pattern: #"(?i)\s+(?:helper|web content|networking|renderer|gpu|plugin)(?:\s*\([^)]*\))?$"#
    )

    private struct Descriptor {
        let key: String
        let name: String
        let kind: SystemProcessGroup.Kind
        let app: SystemApp?
    }

    private struct Bucket {
        let name: String
        let kind: SystemProcessGroup.Kind
        let app: SystemApp?
        var processes: [SystemProcess]
    }

    static func groups(for info: SystemInfo) -> [SystemProcessGroup] {
        groups(processes: info.processes.all, apps: info.apps)
    }

    static func groups(processes: [SystemProcess], apps: [SystemApp]) -> [SystemProcessGroup] {
        let appIndex = makeAppIndex(apps)
        var buckets: [String: Bucket] = [:]

        for process in processes {
            let descriptor = describe(process, apps: apps, appIndex: appIndex)
            if var bucket = buckets[descriptor.key] {
                bucket.processes.append(process)
                buckets[descriptor.key] = bucket
            } else {
                buckets[descriptor.key] = Bucket(
                    name: descriptor.name,
                    kind: descriptor.kind,
                    app: descriptor.app,
                    processes: [process]
                )
            }
        }

        return buckets.map { key, bucket in
            SystemProcessGroup(
                id: key,
                name: bucket.name,
                kind: bucket.kind,
                processes: bucket.processes.sorted {
                    ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0)
                },
                app: bucket.app
            )
        }
        .sorted {
            if $0.totalMemoryBytes == $1.totalMemoryBytes {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.totalMemoryBytes > $1.totalMemoryBytes
        }
    }

    /// Context for one process, even when it was not part of a grouped list.
    static func group(for process: SystemProcess, apps: [SystemApp]) -> SystemProcessGroup {
        groups(processes: [process], apps: apps).first
            ?? SystemProcessGroup(
                id: "process:\(process.pid)",
                name: process.name,
                kind: .process,
                processes: [process],
                app: nil
            )
    }

    /// The `.app` bundle prefix of a process command. "Google Chrome Helper"
    /// lives under `Google Chrome.app/Contents/Frameworks/...`, so the group is
    /// the same as the browser's main process.
    static func applicationPath(for process: SystemProcess) -> String? {
        guard let command = process.command?.trimmingCharacters(in: .whitespacesAndNewlines),
              !command.isEmpty
        else { return nil }

        guard let regex = bundleRegex else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, range: range),
              let bundleRange = Range(match.range(at: 1), in: command)
        else { return nil }
        return String(command[bundleRange])
    }

    static func normalizedName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return name }

        guard let regex = helperRegex else { return trimmed }
        var result = trimmed
        // A few Electron helpers repeat the pattern, e.g. "Foo Helper Helper".
        while true {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            guard let match = regex.firstMatch(in: result, range: range),
                  let matchRange = Range(match.range, in: result)
            else { break }
            let candidate = String(result[..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { break }
            result = candidate
        }
        return result
    }

    // MARK: - Private

    private static func describe(
        _ process: SystemProcess,
        apps: [SystemApp],
        appIndex: [String: SystemApp]
    ) -> Descriptor {
        if let bundlePath = applicationPath(for: process) {
            let name = bundleDisplayName(bundlePath, fallback: process.name)
            let app = appIndex[bundlePath.lowercased()]
                ?? apps.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            return Descriptor(
                key: "app:" + bundlePath.lowercased(),
                name: app?.name ?? name,
                kind: .application,
                app: app
            )
        }

        let name = normalizedName(process.name)
        if let app = apps.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) {
            return Descriptor(
                key: "app:" + app.path.lowercased(),
                name: app.name,
                kind: .application,
                app: app
            )
        }

        return Descriptor(
            key: "process:" + name.lowercased(),
            name: name,
            kind: .process,
            app: nil
        )
    }

    private static func makeAppIndex(_ apps: [SystemApp]) -> [String: SystemApp] {
        var index: [String: SystemApp] = [:]
        for app in apps where !app.path.isEmpty {
            index[app.path.lowercased()] = app
        }
        return index
    }

    private static func bundleDisplayName(_ path: String, fallback: String) -> String {
        let name = URL(fileURLWithPath: path)
            .deletingPathExtension()
            .lastPathComponent
        return name.isEmpty ? fallback : name
    }
}

/// Aggregate numbers for the "Process footprint" card. Keeping this shared
/// means the Mac and iOS memory pages describe the bounded snapshot the same way.
struct SystemProcessSummary {
    let totalCount: Int
    let listedCount: Int
    let groupCount: Int
    let listedMemoryBytes: Int64
    let usedMemoryBytes: Int64
    let userCount: Int
    let topGroup: SystemProcessGroup?
    let topProcess: SystemProcess?

    var listedFractionOfUsed: Double {
        guard usedMemoryBytes > 0 else { return 0 }
        return min(1, max(0, Double(listedMemoryBytes) / Double(usedMemoryBytes)))
    }

    var outsideListBytes: Int64 {
        max(0, usedMemoryBytes - listedMemoryBytes)
    }

    static func make(info: SystemInfo, groups: [SystemProcessGroup]) -> SystemProcessSummary {
        let processes = info.processes.all
        let users = Set(processes.compactMap(\.user).filter { !$0.isEmpty })
        let topProcess = processes.max {
            ($0.memoryBytes ?? 0) < ($1.memoryBytes ?? 0)
        }
        return SystemProcessSummary(
            totalCount: info.processes.total,
            listedCount: processes.count,
            groupCount: groups.count,
            listedMemoryBytes: processes.reduce(0) { $0 + ($1.memoryBytes ?? 0) },
            usedMemoryBytes: info.memory.usedBytes,
            userCount: users.count,
            topGroup: groups.max { $0.totalMemoryBytes < $1.totalMemoryBytes },
            topProcess: topProcess
        )
    }
}

/// A coarse pressure estimate derived from reclaimable memory. macOS reports
/// "available" as free plus inactive pages, so this tracks the same signal as
/// Activity Monitor's Memory Pressure graph without needing another collector.
enum SystemMemoryPressure: String, Sendable {
    case normal
    case elevated
    case critical

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .elevated: return "Elevated"
        case .critical: return "Critical"
        }
    }

    var detail: String {
        switch self {
        case .normal:
            return "Plenty of reclaimable memory is available."
        case .elevated:
            return "Available memory is getting low; the system may start compressing pages."
        case .critical:
            return "Very little memory is reclaimable; apps may be swapped or terminated."
        }
    }
}

extension SystemMemory {
    var availableOrFreeBytes: Int64 {
        availableBytes ?? freeBytes
    }

    var estimatedPressure: SystemMemoryPressure {
        guard totalBytes > 0 else { return .normal }
        let fraction = Double(availableOrFreeBytes) / Double(totalBytes)
        if fraction < 0.08 { return .critical }
        if fraction < 0.18 { return .elevated }
        return .normal
    }

    var swapUsedFraction: Double {
        guard let total = swapTotalBytes, total > 0 else { return 0 }
        return min(1, max(0, Double(swapUsedBytes ?? 0) / Double(total)))
    }
}

extension SystemProcess {
    /// Only absolute commands can be opened in the file browser or split into
    /// an executable and directory.
    var executablePath: String? {
        guard let command = command?.trimmingCharacters(in: .whitespacesAndNewlines),
              command.hasPrefix("/")
        else { return nil }
        return command
    }

    var executableName: String {
        if let executablePath {
            let name = URL(fileURLWithPath: executablePath).lastPathComponent
            if !name.isEmpty { return name }
        }
        return name
    }

    var directoryPath: String? {
        executablePath.map {
            URL(fileURLWithPath: $0).deletingLastPathComponent().path
        }
    }

    var stateDescription: String? {
        guard let state, let flag = state.first else { return nil }
        switch flag {
        case "R": return "Running"
        case "S": return "Sleeping"
        case "T": return "Stopped"
        case "Z": return "Zombie"
        case "I": return "Idle"
        case "D", "U": return "Uninterruptible"
        default: return nil
        }
    }
}
