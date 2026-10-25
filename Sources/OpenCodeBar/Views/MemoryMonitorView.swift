import AppKit
import SwiftUI

/// Activity Monitor-style memory detail opened from the System overview tile.
/// The page reads the live `AppState.systemInfo` snapshot, so the five-second
/// System poll keeps both the breakdown and the process list current.
struct MemoryMonitorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var sort: ProcessSort = .memory
    @State private var selectedProcess: SystemProcess?
    @State private var selectedGroup: SystemProcessGroup?

    /// Helper processes are folded into their owning app by default; the
    /// preference survives reopening the monitor.
    @AppStorage("system.memory.groupApps") private var groupApps = true

    private var info: SystemInfo? { state.systemInfo }

    private enum ProcessSort: String, CaseIterable, Identifiable {
        case memory = "Memory"
        case cpu = "CPU"
        case name = "Name"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if let info {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary(info.memory)
                        processes(info)
                        processInsights(info)
                        breakdown(info.memory)
                        swapSection(info.memory)
                        footnote(info)
                    }
                    .padding(14)
                }
            } else if let error = state.systemInfoError {
                EmptyState(
                    icon: "memorychip",
                    title: "Memory information unavailable",
                    subtitle: error
                )
                .padding(14)
            } else {
                VStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Reading memory usage…")
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 560, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await state.refreshSystemInfo() }
        .sheet(item: $selectedProcess) { process in
            MemoryProcessDetailView(process: process)
                .environmentObject(state)
        }
        .sheet(item: $selectedGroup) { group in
            MemoryProcessGroupDetailView(group: group)
                .environmentObject(state)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "memorychip")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.reasoning)

            VStack(alignment: .leading, spacing: 1) {
                Text("Memory")
                    .font(.system(size: 14, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let fetched = state.systemInfoFetchedAt {
                Text("Updated \(Fmt.relative(from: fetched))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Button {
                Task { await state.refreshSystemInfo(force: true) }
            } label: {
                if state.isRefreshingSystemInfo {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(state.isRefreshingSystemInfo)
            .help("Refresh memory information")
            .accessibilityLabel("Refresh memory information")

            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var headerSubtitle: String {
        guard let info else { return "Hub host" }
        let system = [info.host.osName, info.host.osVersion].compactMap { $0 }.joined(separator: " ")
        return [info.host.name, system].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Summary

    private func summary(_ memory: SystemMemory) -> some View {
        let pressure = memory.estimatedPressure
        return VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(Fmt.bytes(memory.usedBytes))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("used of \(Fmt.bytes(memory.totalBytes))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(Int((memory.usedFraction * 100).rounded()))%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.reasoning)
            }

            UsageBar(fraction: memory.usedFraction, tint: Theme.reasoning, height: 7)
                .accessibilityLabel("Memory used")
                .accessibilityValue("\(Int((memory.usedFraction * 100).rounded())) percent")

            HStack(spacing: 22) {
                metric("Used", Fmt.bytes(memory.usedBytes))
                metric("Free", Fmt.bytes(memory.freeBytes))
                metric("Available", Fmt.bytes(memory.availableOrFreeBytes))
                if let cached = memory.cachedBytes {
                    metric("Cached", Fmt.bytes(cached))
                }
            }

            HStack(alignment: .top, spacing: 8) {
                Chip(
                    text: "Pressure: \(pressure.label)",
                    systemImage: pressureIcon(pressure),
                    tint: pressureTint(pressure)
                )
                Text(pressure.detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    // MARK: - Breakdown

    private struct BreakdownItem: Identifiable {
        let label: String
        let bytes: Int64
        let tint: Color
        let detail: String

        var id: String { label }
    }

    private func breakdown(_ memory: SystemMemory) -> some View {
        let items = breakdownItems(memory)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Breakdown") {
                Text("of \(Fmt.bytes(memory.totalBytes))")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 9) {
                if items.isEmpty {
                    Text("The hub did not report a page breakdown for this host.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(item.tint)
                                    .frame(width: 6, height: 6)
                                Text(item.label)
                                    .font(.system(size: 10, weight: .medium))
                                Spacer(minLength: 8)
                                Text(Fmt.bytes(item.bytes))
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text(percent(item.bytes, of: memory.totalBytes))
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 42, alignment: .trailing)
                            }
                            UsageBar(fraction: fraction(item.bytes, of: memory.totalBytes), tint: item.tint, height: 3)
                        }
                        .help(item.detail)
                    }
                }
            }
            .card()
        }
    }

    private func breakdownItems(_ memory: SystemMemory) -> [BreakdownItem] {
        var items: [BreakdownItem] = []
        if let value = memory.activeBytes {
            items.append(BreakdownItem(
                label: "Active",
                bytes: value,
                tint: Theme.input,
                detail: "Pages currently mapped and in use."
            ))
        }
        if let value = memory.inactiveBytes {
            items.append(BreakdownItem(
                label: "Inactive",
                bytes: value,
                tint: Theme.output,
                detail: "Recently used pages that can be reclaimed without writing them to disk."
            ))
        }
        if let value = memory.wiredBytes {
            items.append(BreakdownItem(
                label: "Wired",
                bytes: value,
                tint: Theme.warn,
                detail: "Kernel and driver pages that cannot be paged out."
            ))
        }
        if let value = memory.compressedBytes {
            items.append(BreakdownItem(
                label: "Compressed",
                bytes: value,
                tint: Theme.reasoning,
                detail: "Pages the memory compressor has packed to make room."
            ))
        }
        if let value = memory.cachedBytes {
            items.append(BreakdownItem(
                label: "Cached files",
                bytes: value,
                tint: Theme.cacheRead,
                detail: "Reclaimable file-backed pages kept to speed up reads."
            ))
        }
        return items
    }

    // MARK: - Swap

    @ViewBuilder
    private func swapSection(_ memory: SystemMemory) -> some View {
        if let total = memory.swapTotalBytes, total > 0 {
            let used = memory.swapUsedBytes ?? 0
            let swapFraction = memory.swapUsedFraction
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Swap") {
                    Text("\(Fmt.bytes(used)) / \(Fmt.bytes(total))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 9) {
                    UsageBar(
                        fraction: swapFraction,
                        tint: swapFraction > 0.75 ? Theme.warn : Theme.cacheRead
                    )
                    HStack(spacing: 22) {
                        metric("Used", Fmt.bytes(used))
                        metric("Free", Fmt.bytes(memory.swapFreeBytes))
                        metric("Total", Fmt.bytes(total))
                        if let swapPercent = memory.swapUsedBytes.map({ percent($0, of: total) }) {
                            metric("Usage", swapPercent)
                        }
                    }
                }
                .card()
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Swap")
                VStack(alignment: .leading, spacing: 4) {
                    Text("No swap space reported")
                        .font(.system(size: 10, weight: .medium))
                    Text("The hub did not report a swap device or swap file for this host.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
        }
    }

    // MARK: - Process insights

    private func processInsights(_ info: SystemInfo) -> some View {
        let groups = SystemProcessGrouping.groups(for: info)
        let summary = SystemProcessSummary.make(info: info, groups: groups)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Process footprint") {
                Text("\(summary.listedCount) of \(Fmt.grouped(summary.totalCount)) listed")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 22) {
                    metric("In list", Fmt.bytes(summary.listedMemoryBytes))
                    metric("Of used", percent(summary.listedMemoryBytes, of: summary.usedMemoryBytes))
                    metric("Outside list", Fmt.bytes(summary.outsideListBytes))
                    metric(groupApps ? "Groups" : "Users", groupApps ? "\(summary.groupCount)" : "\(summary.userCount)")
                }

                UsageBar(fraction: summary.listedFractionOfUsed, tint: Theme.reasoning, height: 3)
                Text("The hub sends a bounded process list, so everything else appears under “Outside list”. Resident sizes can overlap, so totals are approximate.")
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.5)
                topConsumer(summary)
            }
            .card()
        }
    }

    @ViewBuilder
    private func topConsumer(_ summary: SystemProcessSummary) -> some View {
        if groupApps, let group = summary.topGroup {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.reasoning)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Largest app group")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                    Text(group.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.bytes(group.totalMemoryBytes))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(group.processCount) processes")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        } else if let process = summary.topProcess {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.reasoning)
                    .frame(width: 6, height: 6)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Largest process")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                    Text(process.name)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.bytes(process.memoryBytes))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("PID \(process.pid)")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Processes

    private func processes(_ info: SystemInfo) -> some View {
        let all = info.processes.all
        let filtered = filtered(all)
        let groups = sortedGroups(SystemProcessGrouping.groups(processes: filtered, apps: info.apps))
        let rows = sortedProcesses(filtered)
        let rowCount = groupApps ? groups.count : rows.count

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(groupApps ? "Grouped by app" : "Processes by memory") {
                Text("\(Fmt.grouped(info.processes.total)) total")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 9) {
                searchField
                controls
                HStack {
                    Text(processCountLabel(groups: groups, rows: rows, listed: all.count, total: info.processes.total))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text(sort == .cpu ? "CPU" : "MEMORY")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                }

                if rowCount == 0 {
                    Text("No matching process. Try a different name, PID or user.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else if groupApps {
                    VStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            Button {
                                selectedGroup = group
                            } label: {
                                groupRow(group, totalBytes: info.memory.totalBytes)
                            }
                            .buttonStyle(.plain)
                            if index < groups.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, process in
                            Button {
                                selectedProcess = process
                            } label: {
                                processRow(process)
                            }
                            .buttonStyle(.plain)
                            if index < rows.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }

                Text(
                    groupApps
                        ? "Processes are folded into their owning app when one can be detected, otherwise by executable name. Totals cover the \(all.count) processes in this snapshot."
                        : "Showing the \(all.count) processes included in this snapshot."
                )
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter by app, process, PID or user", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $groupApps) {
                Text("Group by app")
                    .font(.system(size: 9.5, weight: .medium))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help("Fold helper and renderer processes under their owning application")

            Spacer(minLength: 6)

            Picker("Sort", selection: $sort) {
                ForEach(ProcessSort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 168)
            .help("Sort processes")
        }
    }

    private func groupRow(_ group: SystemProcessGroup, totalBytes: Int64) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let app = group.app {
                AppIconView(
                    api: state.api,
                    path: app.path,
                    hasIcon: app.hasIcon == true,
                    size: 22
                )
            } else {
                Image(systemName: group.isApplication ? "app" : "gearshape.2")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(group.isApplication ? Theme.accent : .secondary)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("\(group.processCount) \(group.processCount == 1 ? "process" : "processes")")
                    if let user = group.users.first, !user.isEmpty {
                        Text("·")
                        Text(user)
                        if group.users.count > 1 {
                            Text("+\(group.users.count - 1)")
                        }
                    }
                    if group.totalCPUPercent > 0.05 {
                        Text("·")
                        Text(String(format: "%.1f%% CPU", group.totalCPUPercent))
                    }
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.bytes(group.totalMemoryBytes))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(percent(group.totalMemoryBytes, of: totalBytes))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(width: 78, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help("Show every process in \(group.name)")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens details for \(group.name)")
    }

    private func processRow(_ process: SystemProcess) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(process.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("PID \(process.pid)")
                        .font(.system(size: 8, design: .monospaced))
                    if let user = process.user, !user.isEmpty {
                        Text("·")
                        Text(user)
                            .font(.system(size: 8))
                            .lineLimit(1)
                    }
                    if let state = process.state, !state.isEmpty {
                        Text("·")
                        Text(state)
                            .font(.system(size: 8, design: .monospaced))
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.bytes(process.memoryBytes))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    if let percent = process.memoryPercent {
                        Text(String(format: "%.1f%% mem", percent))
                    }
                    if let cpu = process.cpuPercent, cpu >= 0.05 {
                        Text("·")
                        Text(String(format: "%.1f%% CPU", cpu))
                    }
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            .frame(width: 104, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(process.command ?? process.name)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens process details")
    }

    private func processCountLabel(
        groups: [SystemProcessGroup],
        rows: [SystemProcess],
        listed: Int,
        total: Int
    ) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if groupApps {
            if groups.isEmpty { return "No matching group" }
            if trimmed.isEmpty {
                return "\(groups.count) \(groups.count == 1 ? "group" : "groups") · \(rows.count) of \(Fmt.grouped(total)) processes"
            }
            return "\(groups.count) matching \(groups.count == 1 ? "group" : "groups") · \(rows.count) processes"
        }
        if rows.isEmpty { return "No matching process" }
        if trimmed.isEmpty {
            return "\(rows.count) of \(Fmt.grouped(total)) processes"
        }
        return "\(rows.count) matching of \(listed) listed"
    }

    private func filtered(_ processes: [SystemProcess]) -> [SystemProcess] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return processes }
        return processes.filter { process in
            process.name.lowercased().contains(needle)
                || SystemProcessGrouping.normalizedName(process.name).lowercased().contains(needle)
                || (process.command?.lowercased().contains(needle) ?? false)
                || (process.user?.lowercased().contains(needle) ?? false)
                || String(process.pid).contains(needle)
        }
    }

    private func sortedGroups(_ groups: [SystemProcessGroup]) -> [SystemProcessGroup] {
        switch sort {
        case .memory:
            return groups.sorted {
                if $0.totalMemoryBytes == $1.totalMemoryBytes {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.totalMemoryBytes > $1.totalMemoryBytes
            }
        case .cpu:
            return groups.sorted {
                if abs($0.totalCPUPercent - $1.totalCPUPercent) < 0.000_1 {
                    return $0.totalMemoryBytes > $1.totalMemoryBytes
                }
                return $0.totalCPUPercent > $1.totalCPUPercent
            }
        case .name:
            return groups.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func sortedProcesses(_ processes: [SystemProcess]) -> [SystemProcess] {
        switch sort {
        case .memory:
            return processes.sorted {
                if ($0.memoryBytes ?? 0) == ($1.memoryBytes ?? 0) {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0)
            }
        case .cpu:
            return processes.sorted {
                if ($0.cpuPercent ?? 0) == ($1.cpuPercent ?? 0) {
                    return ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0)
                }
                return ($0.cpuPercent ?? 0) > ($1.cpuPercent ?? 0)
            }
        case .name:
            return processes.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private func footnote(_ info: SystemInfo) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 8, weight: .semibold))
            Text("Snapshot \(info.generatedDate.formatted(date: .abbreviated, time: .standard)) · Hub \(info.hub.version)")
                .font(.system(size: 8.5))
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    // MARK: - Helpers

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

    private func pressureTint(_ pressure: SystemMemoryPressure) -> Color {
        switch pressure {
        case .normal: return Theme.accent
        case .elevated: return Theme.warn
        case .critical: return Theme.danger
        }
    }

    private func pressureIcon(_ pressure: SystemMemoryPressure) -> String {
        switch pressure {
        case .normal: return "checkmark.circle"
        case .elevated: return "exclamationmark.triangle"
        case .critical: return "exclamationmark.octagon"
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
