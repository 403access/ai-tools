import SwiftUI

/// Activity Monitor-style memory page pushed from the System overview tile.
/// The parent System view keeps polling the hub every five seconds, so the
/// breakdown and process list stay live while this page is open.
struct MobileMemoryMonitorView: View {
    @EnvironmentObject private var store: MobileStore

    @State private var query = ""

    private var info: SystemInfo? { store.systemInfo }

    var body: some View {
        Group {
            if let info {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        summary(info.memory)
                        breakdown(info.memory)
                        swapSection(info.memory)
                        processes(info.processes)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            } else if let error = store.systemInfoError {
                ScrollView {
                    EmptyState(
                        icon: "memorychip",
                        title: "Memory information unavailable",
                        subtitle: error
                    )
                    .padding(16)
                }
            } else {
                ScrollView {
                    LoadingState(message: "Reading memory usage…")
                        .padding(16)
                }
            }
        }
        .mobileScreenBackground()
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshSystemInfo(force: true) }
                } label: {
                    if store.isRefreshingSystemInfo {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshingSystemInfo)
                .accessibilityLabel("Refresh memory information")
            }
        }
        .refreshable { await store.refreshSystemInfo(force: true) }
        .task { await store.refreshSystemInfo() }
    }

    // MARK: - Summary

    private func summary(_ memory: SystemMemory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.bytes(memory.usedBytes))
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("used of \(Fmt.bytes(memory.totalBytes))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text("\(Int((memory.usedFraction * 100).rounded()))%")
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.reasoning)
            }

            MobileSystemBar(fraction: memory.usedFraction, tint: Theme.reasoning, height: 8)
                .accessibilityLabel("Memory used")
                .accessibilityValue("\(Int((memory.usedFraction * 100).rounded())) percent")

            HStack(spacing: 18) {
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
            VStack(alignment: .leading, spacing: 12) {
                if items.isEmpty {
                    Text("The hub did not report a page breakdown for this host.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(item.tint)
                                    .frame(width: 7, height: 7)
                                Text(item.label)
                                    .font(.caption.weight(.medium))
                                Spacer(minLength: 8)
                                Text(Fmt.bytes(item.bytes))
                                    .font(.caption.weight(.semibold))
                                    .monospacedDigit()
                                Text(percent(item.bytes, of: memory.totalBytes))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: 48, alignment: .trailing)
                            }
                            MobileSystemBar(
                                fraction: fraction(item.bytes, of: memory.totalBytes),
                                tint: item.tint,
                                height: 4
                            )
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
            let usedFraction = total > 0 ? Double(used) / Double(total) : 0
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Swap") {
                    Text("\(Fmt.bytes(used)) / \(Fmt.bytes(total))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                VStack(alignment: .leading, spacing: 12) {
                    MobileSystemBar(
                        fraction: usedFraction,
                        tint: usedFraction > 0.75 ? Theme.warn : Theme.cacheRead
                    )
                    HStack(spacing: 18) {
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 11) {
                searchField

                HStack {
                    Text(processCountLabel(rows, processes: processes))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text("MEMORY")
                        .font(.caption2.weight(.bold))
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

                Text("Largest processes in the current hub snapshot.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter by name, PID or user", text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func processRow(_ process: SystemProcess) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(process.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text("PID \(process.pid)")
                        .font(.caption2.monospaced())
                    if let user = process.user, !user.isEmpty {
                        Text("·")
                        Text(user)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Fmt.bytes(process.memoryBytes))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let percent = process.memoryPercent {
                    Text(String(format: "%.1f%%", percent))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 82, alignment: .trailing)
        }
        .padding(.vertical, 7)
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
        String(format: "%.1f%%", fraction(value, of: total) * 100)
    }
}
