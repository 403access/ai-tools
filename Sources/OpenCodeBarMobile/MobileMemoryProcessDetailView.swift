import SwiftUI
import UIKit

/// Detail page for one process opened from the memory monitor. The parent
/// System page keeps polling, so the figures refresh while this page is pushed.
struct MobileMemoryProcessDetailView: View {
    @EnvironmentObject private var store: MobileStore

    let process: SystemProcess

    private var info: SystemInfo? { store.systemInfo }

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                identity
                overview
                details
                if group.processCount > 1 {
                    groupSection
                }
                if let app {
                    MobileMemoryAppCard(app: app)
                }
                if let info {
                    snapshotLine(info)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .mobileScreenBackground()
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let directory = live.directoryPath {
                    NavigationLink {
                        MobileFileBrowserView(startPath: directory)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("Browse executable folder")
                }
                if let command = live.command {
                    Button {
                        UIPasteboard.general.string = command
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy process command")
                }
            }
        }
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(spacing: 12) {
            if let app {
                AppIconView(
                    api: store.api,
                    path: app.path,
                    hasIcon: app.hasIcon == true,
                    size: 44
                )
            } else {
                Image(systemName: group.isApplication ? "app" : "gearshape.2")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(group.isApplication ? Theme.accent : Theme.reasoning)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(live.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(live.command ?? "PID \(live.pid)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text("PID \(live.pid)")
                    if let user = live.user, !user.isEmpty {
                        Text("·")
                        Text(user)
                    }
                    if let parentPID = live.parentPID {
                        Text("·")
                        Text("parent \(parentPID)")
                    }
                    if group.processCount > 1 {
                        Text("·")
                        Text("\(group.processCount) in \(group.name)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
    }

    // MARK: - Overview

    private var overview: some View {
        let totalMemory = info?.memory.totalBytes ?? 0
        let usedMemory = info?.memory.usedBytes ?? 0
        let resident = live.memoryBytes ?? 0
        let ofRAM = fraction(resident, of: totalMemory)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.bytes(resident))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("resident")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                if let percent = live.memoryPercent {
                    Text(String(format: "%.1f%%", percent))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.reasoning)
                }
            }

            MobileSystemBar(fraction: ofRAM, tint: Theme.reasoning, height: 8)
                .accessibilityLabel("Share of physical memory")
                .accessibilityValue(percent(resident, of: totalMemory))

            HStack(spacing: 16) {
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
            VStack(alignment: .leading, spacing: 9) {
                MobileSystemRow("PID", "\(live.pid)", monospaced: true)
                if let parentPID = live.parentPID {
                    let value = parentProcess.map { "\($0.name) (\(parentPID))" } ?? "\(parentPID)"
                    MobileSystemRow("Parent", value, monospaced: parentProcess == nil)
                }
                if let user = live.user, !user.isEmpty {
                    MobileSystemRow("User", user)
                }
                if let state = live.state, !state.isEmpty {
                    let description = live.stateDescription.map { " · \($0)" } ?? ""
                    MobileSystemRow("State", state + description, monospaced: live.stateDescription == nil)
                }
                if let elapsed = live.elapsedSeconds {
                    MobileSystemRow("Running for", Fmt.uptime(elapsed))
                }
                if let cpu = live.cpuPercent {
                    MobileSystemRow("CPU", String(format: "%.1f%%", cpu))
                }
                if let memoryPercent = live.memoryPercent {
                    MobileSystemRow("Memory", String(format: "%.1f%% of physical memory", memoryPercent))
                }
                Divider().opacity(0.5)
                MobileSystemRow("Executable", live.executableName, monospaced: true)
                if let directory = live.directoryPath {
                    MobileSystemRow("Directory", directory, monospaced: true)
                }
                if group.processCount > 1 {
                    MobileSystemRow("Group", "\(group.name) · \(group.processCount) processes")
                }
                if let command = live.command, !command.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMMAND")
                            .font(.caption2.weight(.bold))
                            .tracking(0.4)
                            .foregroundStyle(.tertiary)
                        Text(command)
                            .font(.caption2.monospaced())
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(spacing: 0) {
                ForEach(Array(group.processes.enumerated()), id: \.element.id) { index, member in
                    if member.pid == live.pid {
                        MobileMemoryMemberRow(
                            process: member,
                            totalBytes: group.totalMemoryBytes,
                            isCurrent: true
                        )
                    } else {
                        NavigationLink {
                            MobileMemoryProcessDetailView(process: member)
                        } label: {
                            MobileMemoryMemberRow(
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
                .font(.caption2.weight(.semibold))
            Text("Snapshot \(info.generatedDate.formatted(date: .abbreviated, time: .standard)) · Hub \(info.hub.version)")
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold))
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
}

/// Detail page for an app group. Members stay tappable so the user can drill
/// from "Google Chrome" into one renderer or plugin process.
struct MobileMemoryProcessGroupDetailView: View {
    @EnvironmentObject private var store: MobileStore

    let group: SystemProcessGroup

    private var info: SystemInfo? { store.systemInfo }

    private var live: SystemProcessGroup {
        guard let info,
              let match = SystemProcessGrouping.groups(for: info)
                .first(where: { $0.id == group.id })
        else { return group }
        return match
    }

    private var app: SystemApp? { live.app }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                identity
                overview
                processes
                if let app {
                    MobileMemoryAppCard(app: app)
                }
                if let info {
                    snapshotLine(info)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .mobileScreenBackground()
        .navigationTitle(live.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Identity

    private var identity: some View {
        HStack(spacing: 12) {
            if let app {
                AppIconView(
                    api: store.api,
                    path: app.path,
                    hasIcon: app.hasIcon == true,
                    size: 44
                )
            } else {
                Image(systemName: live.isApplication ? "app" : "gearshape.2")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(live.isApplication ? Theme.accent : Theme.reasoning)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(live.name)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(live.processCount) \(live.processCount == 1 ? "process" : "processes")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !live.users.isEmpty {
                    Text(live.users.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
    }

    // MARK: - Overview

    private var overview: some View {
        let totalMemory = info?.memory.totalBytes ?? 0
        let usedMemory = info?.memory.usedBytes ?? 0
        let groupMemory = live.totalMemoryBytes
        let ofRAM = fraction(groupMemory, of: totalMemory)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.bytes(groupMemory))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("combined resident")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("\(live.processCount)")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.reasoning)
                Text(live.processCount == 1 ? "process" : "processes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            MobileSystemBar(fraction: ofRAM, tint: Theme.reasoning, height: 8)
                .accessibilityLabel("Share of physical memory")
                .accessibilityValue(percent(groupMemory, of: totalMemory))

            HStack(spacing: 16) {
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(spacing: 0) {
                ForEach(Array(live.processes.enumerated()), id: \.element.id) { index, process in
                    NavigationLink {
                        MobileMemoryProcessDetailView(process: process)
                    } label: {
                        MobileMemoryMemberRow(
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
                .font(.caption2.weight(.semibold))
            Text("Snapshot \(info.generatedDate.formatted(date: .abbreviated, time: .standard)) · Hub \(info.hub.version)")
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold))
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

private struct MobileMemoryMemberRow: View {
    let process: SystemProcess
    let totalBytes: Int64
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: isCurrent ? "smallcircle.filled.circle" : "circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isCurrent ? Theme.accent : Color.secondary.opacity(0.5))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.subheadline.weight(isCurrent ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("PID \(process.pid)")
                        .font(.caption2.monospaced())
                    if let user = process.user, !user.isEmpty {
                        Text("·")
                        Text(user)
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.bytes(process.memoryBytes))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(percent(process.memoryBytes ?? 0, of: totalBytes))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 80, alignment: .trailing)

            if isCurrent {
                Text("CURRENT")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, alignment: .trailing)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func percent(_ value: Int64, of total: Int64) -> String {
        guard total > 0 else { return "—" }
        return String(format: "%.1f%%", min(1, Double(value) / Double(total)) * 100)
    }
}

private struct MobileMemoryAppCard: View {
    let app: SystemApp

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Application") {
                if let version = app.version {
                    Chip(text: version, systemImage: "shippingbox", tint: Theme.cacheRead)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                if let bundleID = app.bundleID {
                    MobileSystemRow("Bundle ID", bundleID, monospaced: true)
                }
                if let version = app.version {
                    MobileSystemRow("Version", version)
                }
                if let source = app.source {
                    MobileSystemRow("Source", sourceLabel(source))
                }
                if let architecture = app.architecture {
                    MobileSystemRow("Architecture", architecture)
                }
                MobileSystemRow("Path", app.path, monospaced: true)
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
