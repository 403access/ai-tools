import AppKit
import SwiftUI

/// Activity Monitor-style memory detail opened from the System overview tile.
/// The page reads the live `AppState.systemInfo` snapshot, so the five-second
/// System poll keeps both the breakdown and the process list current.
struct MemoryMonitorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""

    private var info: SystemInfo? { state.systemInfo }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if let info {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary(info.memory)
                        breakdown(info.memory)
                        swapSection(info.memory)
                        processes(info.processes)
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
        VStack(alignment: .leading, spacing: 11) {
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
                metric("Available", Fmt.bytes(memory.availableBytes ?? memory.freeBytes))
                if let cached = memory.cachedBytes {
                    metric("Cached", Fmt.bytes(cached))
                }
            }
        }
        .card()
    }

    // MARK: - Breakdown

    private struct BreakdownItem: Identifiable {
        let label: String
        let bytes: Int64
        let tint: Color

        var id: String { label }
    }

    private func breakdown(_ memory: SystemMemory) -> some View {
        let items = breakdownItems(memory)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Breakdown")
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
                    }
                }
            }
            .card()
        }
    }

    private func breakdownItems(_ memory: SystemMemory) -> [BreakdownItem] {
        var items: [BreakdownItem] = []
        if let value = memory.activeBytes {
            items.append(BreakdownItem(label: "Active", bytes: value, tint: Theme.input))
        }
        if let value = memory.inactiveBytes {
            items.append(BreakdownItem(label: "Inactive", bytes: value, tint: Theme.output))
        }
        if let value = memory.wiredBytes {
            items.append(BreakdownItem(label: "Wired", bytes: value, tint: Theme.warn))
        }
        if let value = memory.compressedBytes {
            items.append(BreakdownItem(label: "Compressed", bytes: value, tint: Theme.reasoning))
        }
        if let value = memory.cachedBytes {
            items.append(BreakdownItem(label: "Cached files", bytes: value, tint: Theme.cacheRead))
        }
        return items
    }

    // MARK: - Swap

    @ViewBuilder
    private func swapSection(_ memory: SystemMemory) -> some View {
        if let total = memory.swapTotalBytes, total > 0 {
            let used = memory.swapUsedBytes ?? 0
            let fraction = total > 0 ? Double(used) / Double(total) : 0
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Swap") {
                    Text("\(Fmt.bytes(used)) / \(Fmt.bytes(total))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 9) {
                    UsageBar(
                        fraction: fraction,
                        tint: fraction > 0.75 ? Theme.warn : Theme.cacheRead
                    )
                    HStack(spacing: 22) {
                        metric("Used", Fmt.bytes(used))
                        metric("Free", Fmt.bytes(memory.swapFreeBytes))
                        metric("Total", Fmt.bytes(total))
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Processes

    private func processes(_ processes: SystemProcesses) -> some View {
        let rows = filtered(processes.topMemory)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Processes by memory") {
                Text("\(Fmt.grouped(processes.total)) total")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 9) {
                searchField

                HStack {
                    Text(processCountLabel(rows, processes: processes))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text("MEMORY")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                }

                if !rows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, process in
                            processRow(process)
                            if index < rows.count - 1 {
                                Divider().opacity(0.4)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter by name, PID or user", text: $query)
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
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.bytes(process.memoryBytes))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                if let percent = process.memoryPercent {
                    Text(String(format: "%.1f%%", percent))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .help(process.command ?? process.name)
        .accessibilityElement(children: .combine)
    }

    private func processCountLabel(_ rows: [SystemProcess], processes: SystemProcesses) -> String {
        if rows.isEmpty { return "No matching process" }
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Top \(rows.count) of \(Fmt.grouped(processes.total)) processes"
        }
        return "\(rows.count) matching of \(processes.topMemory.count) listed"
    }

    private func filtered(_ processes: [SystemProcess]) -> [SystemProcess] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return processes }
        return processes.filter { process in
            process.name.lowercased().contains(needle)
                || (process.command?.lowercased().contains(needle) ?? false)
                || (process.user?.lowercased().contains(needle) ?? false)
                || String(process.pid).contains(needle)
        }
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

    private func fraction(_ value: Int64, of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(value) / Double(total)))
    }

    private func percent(_ value: Int64, of total: Int64) -> String {
        String(format: "%.1f%%", fraction(value, of: total) * 100)
    }
}
