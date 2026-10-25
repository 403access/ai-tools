import AppKit
import SwiftUI

/// Detail sheet for one process opened from the memory monitor. It reads the
/// live snapshot so the numbers keep refreshing while the sheet is open.
struct MemoryProcessDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let process: SystemProcess

    @State private var selectedProcess: SystemProcess?
    @State private var copied = false

    private var info: SystemInfo? { state.systemInfo }

    private var live: SystemProcess {
        info?.processes.all.first { $0.pid == process.pid } ?? process
    }

    private var group: SystemProcessGroup {
        if let info,
           let match = SystemProcessGrouping.groups(for: info)
            .first(where: { $0.processes.contains { $0.pid == process.pid } }) {
            return match
        }
        return SystemProcessGrouping.group(for: process, apps: info?.apps ?? [])
    }

    private var app: SystemApp? { group.app }

    private var parentProcess: SystemProcess? {
        guard let parentPID = live.parentPID else { return nil }
        return info?.processes.all.first { $0.pid == parentPID }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    overview
                    details
                    if group.processCount > 1 {
                        groupSection
                    }
                    if let app {
                        MemoryProcessAppCard(app: app)
                    }
                    if let info {
                        snapshotLine(info)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 560, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedProcess) { member in
            MemoryProcessDetailView(process: member)
                .environmentObject(state)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back to Memory")

            if let app {
                AppIconView(
                    api: state.api,
                    path: app.path,
                    hasIcon: app.hasIcon == true,
                    size: 30
                )
            } else {
                Image(systemName: group.isApplication ? "app" : "gearshape.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(group.isApplication ? Theme.accent : Theme.reasoning)
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(live.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(live.command ?? "PID \(live.pid)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if let command = live.command {
                Button {
                    copy(command)
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(copied ? Theme.accent : .secondary)
                .help("Copy process command")
                .accessibilityLabel("Copy process command")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Overview

    private var overview: some View {
        let totalMemory = info?.memory.totalBytes ?? 0
        let usedMemory = info?.memory.usedBytes ?? 0
        let resident = live.memoryBytes ?? 0
        let ofRAM = fraction(resident, of: totalMemory)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Fmt.bytes(resident))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("resident")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let percent = live.memoryPercent {
                    Text(String(format: "%.1f%%", percent))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.reasoning)
                }
            }

            UsageBar(fraction: ofRAM, tint: Theme.reasoning, height: 7)
                .accessibilityLabel("Share of physical memory")
                .accessibilityValue(percent(resident, of: totalMemory))

            HStack(spacing: 22) {
                metric("Of RAM", totalMemory > 0 ? percent(resident, of: totalMemory) : "—")
                metric("Of used", usedMemory > 0 ? percent(resident, of: usedMemory) : "—")
                metric("CPU", cpuText(live.cpuPercent))
                metric("Virtual", Fmt.bytes(live.virtualMemoryBytes))
            }
        }
        .card()
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Process")
            VStack(alignment: .leading, spacing: 8) {
                MemoryDetailRow("PID", "\(live.pid)", monospaced: true)
                if let parentPID = live.parentPID {
                    let value = parentProcess.map { "\($0.name) (\(parentPID))" } ?? "\(parentPID)"
                    MemoryDetailRow("Parent", value, monospaced: parentProcess == nil)
                }
                if let user = live.user, !user.isEmpty {
                    MemoryDetailRow("User", user)
                }
                if let state = live.state, !state.isEmpty {
                    let description = live.stateDescription.map { " · \($0)" } ?? ""
                    MemoryDetailRow("State", state + description, monospaced: live.stateDescription == nil)
                }
                if let elapsed = live.elapsedSeconds {
                    MemoryDetailRow("Running for", Fmt.uptime(elapsed))
                }
                if let cpu = live.cpuPercent {
                    MemoryDetailRow("CPU", String(format: "%.1f%%", cpu))
                }
                if let memoryPercent = live.memoryPercent {
                    MemoryDetailRow("Memory", String(format: "%.1f%% of physical memory", memoryPercent))
                }
                Divider().opacity(0.5)
                MemoryDetailRow("Executable", live.executableName, monospaced: true)
                if let directory = live.directoryPath {
                    MemoryDetailRow("Directory", directory, monospaced: true)
                }
                if group.processCount > 1 {
                    MemoryDetailRow("Group", "\(group.name) · \(group.processCount) processes")
                }
                if let command = live.command, !command.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMAND")
                            .font(.system(size: 7.5, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(.tertiary)
                        Text(command)
                            .font(.system(size: 9, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Group

    private var groupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Same application") {
                Text("\(group.processCount) processes · \(Fmt.bytes(group.totalMemoryBytes))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(Array(group.processes.enumerated()), id: \.element.id) { index, member in
                    if member.pid == live.pid {
                        MemoryProcessMemberRow(
                            process: member,
                            totalBytes: group.totalMemoryBytes,
                            isCurrent: true
                        )
                    } else {
                        Button {
                            selectedProcess = member
                        } label: {
                            MemoryProcessMemberRow(
                                process: member,
                                totalBytes: group.totalMemoryBytes,
                                isCurrent: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    if index < group.processes.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Helpers

    private func snapshotLine(_ info: SystemInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 8, weight: .semibold))
            Text("Snapshot \(info.generatedDate.formatted(date: .abbreviated, time: .standard)) · Hub \(info.hub.version)")
                .font(.system(size: 8.5))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 7.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func cpuText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func fraction(_ value: Int64, of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    private func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "—" }
        return String(format: "%.1f%%", fraction(value, of: total) * 100)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }
}

/// Detail sheet for an app group. Members are selectable so the user can drill
/// from "Google Chrome" into one renderer or plugin process.
struct MemoryProcessGroupDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let group: SystemProcessGroup

    @State private var selectedProcess: SystemProcess?

    private var info: SystemInfo? { state.systemInfo }

    private var live: SystemProcessGroup {
        guard let info,
              let match = SystemProcessGrouping.groups(for: info)
                .first(where: { $0.id == group.id })
        else { return group }
        return match
    }

    private var app: SystemApp? { live.app }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    overview
                    processes
                    if let app {
                        MemoryProcessAppCard(app: app)
                    }
                    if let info {
                        snapshotLine(info)
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 560, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(item: $selectedProcess) { process in
            MemoryProcessDetailView(process: process)
                .environmentObject(state)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back to Memory")

            if let app {
                AppIconView(
                    api: state.api,
                    path: app.path,
                    hasIcon: app.hasIcon == true,
                    size: 30
                )
            } else {
                Image(systemName: live.isApplication ? "app" : "gearshape.2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(live.isApplication ? Theme.accent : Theme.reasoning)
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(live.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("\(live.processCount) \(live.processCount == 1 ? "process" : "processes")")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Overview

    private var overview: some View {
        let totalMemory = info?.memory.totalBytes ?? 0
        let usedMemory = info?.memory.usedBytes ?? 0
        let groupMemory = live.totalMemoryBytes
        let ofRAM = fraction(groupMemory, of: totalMemory)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Fmt.bytes(groupMemory))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("combined resident")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(live.processCount)")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.reasoning)
                Text(live.processCount == 1 ? "process" : "processes")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            UsageBar(fraction: ofRAM, tint: Theme.reasoning, height: 7)
                .accessibilityLabel("Share of physical memory")
                .accessibilityValue(percent(groupMemory, of: totalMemory))

            HStack(spacing: 22) {
                metric("Of RAM", totalMemory > 0 ? percent(groupMemory, of: totalMemory) : "—")
                metric("Of used", usedMemory > 0 ? percent(groupMemory, of: usedMemory) : "—")
                metric("CPU", String(format: "%.1f%%", live.totalCPUPercent))
                metric("Users", "\(live.users.count)")
            }
        }
        .card()
    }

    // MARK: - Processes

    private var processes: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Processes") {
                Text("\(live.processCount) members")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(spacing: 0) {
                ForEach(Array(live.processes.enumerated()), id: \.element.id) { index, process in
                    Button {
                        selectedProcess = process
                    } label: {
                        MemoryProcessMemberRow(
                            process: process,
                            totalBytes: live.totalMemoryBytes,
                            isCurrent: false
                        )
                    }
                    .buttonStyle(.plain)
                    if index < live.processes.count - 1 {
                        Divider().opacity(0.4)
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Helpers

    private func snapshotLine(_ info: SystemInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 8, weight: .semibold))
            Text("Snapshot \(info.generatedDate.formatted(date: .abbreviated, time: .standard)) · Hub \(info.hub.version)")
                .font(.system(size: 8.5))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 7.5, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func fraction(_ value: Int64, of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    private func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "—" }
        return String(format: "%.1f%%", fraction(value, of: total) * 100)
    }
}

// MARK: - Shared rows

private struct MemoryProcessMemberRow: View {
    let process: SystemProcess
    let totalBytes: Int64
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: isCurrent ? "smallcircle.filled.circle" : "circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isCurrent ? Theme.accent : Color.secondary.opacity(0.5))
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.system(size: 10.5, weight: isCurrent ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("PID \(process.pid)")
                        .font(.system(size: 8, design: .monospaced))
                    if let user = process.user, !user.isEmpty {
                        Text("·")
                        Text(user)
                            .font(.system(size: 8))
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.bytes(process.memoryBytes))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(percent(process.memoryBytes ?? 0, of: totalBytes))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 76, alignment: .trailing)

            if isCurrent {
                Text("CURRENT")
                    .font(.system(size: 7, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 52, alignment: .trailing)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 52, alignment: .trailing)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(process.command ?? process.name)
        .accessibilityElement(children: .combine)
    }

    private func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "—" }
        return String(format: "%.1f%%", min(1, Double(value) / Double(total)) * 100)
    }
}

private struct MemoryProcessAppCard: View {
    let app: SystemApp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Application") {
                if let version = app.version {
                    Chip(text: version, systemImage: "shippingbox", tint: Theme.cacheRead)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                if let bundleID = app.bundleID {
                    MemoryDetailRow("Bundle ID", bundleID, monospaced: true)
                }
                if let version = app.version {
                    MemoryDetailRow("Version", version)
                }
                if let source = app.source {
                    MemoryDetailRow("Source", sourceLabel(source))
                }
                if let architecture = app.architecture {
                    MemoryDetailRow("Architecture", architecture)
                }
                MemoryDetailRow("Path", app.path, monospaced: true)
            }
            .card()
        }
    }

    private func sourceLabel(_ source: String) -> String {
        switch source.lowercased() {
        case "apple": return "Apple"
        case "mac_app_store": return "Mac App Store"
        case "identified_developer": return "Identified developer"
        default: return source
        }
    }
}

private struct MemoryDetailRow: View {
    let label: String
    let value: String
    var monospaced = false
    var tint: Color = .secondary

    init(_ label: String, _ value: String, monospaced: Bool = false, tint: Color = .secondary) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
        self.tint = tint
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .system(size: 9, design: .monospaced) : .system(size: 10, weight: .medium))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}
