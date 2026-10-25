import SwiftUI

/// The Host → System inventory is split into short, focused pages. The
/// dashboard's live tiles open Performance, Storage, Health and Machine; the
/// "More" grid opens the categories that do not have a matching vital.
enum MobileSystemCategory: String, CaseIterable, Identifiable {
    case performance
    case terminals
    case storage
    case network
    case software
    case files
    case health
    case machine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .performance: return "Performance"
        case .storage: return "Storage"
        case .network: return "Network"
        case .software: return "Software"
        case .health: return "Health"
        case .machine: return "Machine"
        case .terminals: return "Terminals"
        case .files: return "Files"
        }
    }

    var icon: String {
        switch self {
        case .performance: return "gauge.with.dots.needle.67percent"
        case .storage: return "internaldrive"
        case .network: return "network"
        case .software: return "square.stack.3d.up"
        case .health: return "heart.text.square"
        case .machine: return "desktopcomputer"
        case .terminals: return "terminal"
        case .files: return "folder"
        }
    }

    var tint: Color {
        switch self {
        case .performance: return Theme.input
        case .storage: return Theme.cacheRead
        case .network: return Theme.running
        case .software: return Theme.reasoning
        case .health: return Theme.accent
        case .machine: return Theme.accent
        case .terminals: return Theme.output
        case .files: return Theme.cacheRead
        }
    }

    /// Categories that are not already represented by a dashboard vital tile.
    /// Performance, Storage, Health and Machine are reached by tapping the
    /// corresponding live tile, so they do not need a second navigation card.
    var showsInMore: Bool {
        switch self {
        case .performance, .storage, .health, .machine: return false
        case .network, .software, .terminals, .files: return true
        }
    }

    static var moreCases: [MobileSystemCategory] {
        allCases.filter { $0.showsInMore }
    }

    /// One line of live context for a "More" grid tile. Kept short enough to
    /// fit two lines on a narrow phone in a two-column grid.
    @MainActor
    func caption(info: SystemInfo, store: MobileStore) -> String {
        let rootDisk = info.disks.first(where: { $0.mount == "/" }) ?? info.disks.first

        switch self {
        case .performance:
            let cpu = info.cpu.usagePercent.map { "\(Int($0.rounded()))% CPU" }
                ?? "\(info.cpu.logicalCores) cores"
            return "\(cpu) · \(Fmt.bytes(info.memory.usedBytes)) memory"

        case .storage:
            guard !info.disks.isEmpty else { return "No volumes reported" }
            let count = info.disks.count == 1 ? "1 volume" : "\(info.disks.count) volumes"
            return "\(count) · \(Fmt.bytes(rootDisk?.freeBytes)) free"

        case .network:
            let interfaces = info.network.interfaces.filter { interface in
                interface.addresses.contains { !$0.internal_ }
            }
            if let name = info.network.defaultInterface {
                return "\(name) · \(interfaces.count) active interfaces"
            }
            return interfaces.isEmpty ? "No active interfaces" : "\(interfaces.count) active interfaces"

        case .software:
            var parts = ["\(info.apps.count) apps"]
            if let brew = info.homebrew, brew.available {
                parts.append("\(brew.formulaCount + brew.caskCount) packages")
            }
            return parts.joined(separator: " · ")

        case .health:
            let battery = info.battery?.present == true
                ? "Battery \(info.battery?.percent.map { "\($0)%" } ?? "—")"
                : "No battery"
            if let pressure = info.thermal?.pressure {
                return "\(battery) · \(pressure)"
            }
            return battery

        case .machine:
            let os = [info.host.osName, info.host.osVersion]
                .compactMap { $0 }
                .joined(separator: " ")
            return os.isEmpty ? info.host.name : os

        case .terminals:
            return "\(store.terminals.count) shells · \(store.hostTerminals.count) Terminal tabs"

        case .files:
            return "Browse folders on the hub"
        }
    }
}

/// One category page. It reads the live snapshot from the store rather than
/// taking a value, so rows keep updating while the page is open.
struct MobileSystemCategoryView: View {
    let category: MobileSystemCategory

    @EnvironmentObject private var store: MobileStore

    @State private var processMetric: ProcessMetric = .cpu
    @State private var showAllDisks = false
    @State private var showAllApps = false
    @State private var appQuery = ""
    @State private var showAllBrew = false
    @State private var showAllPorts = false
    @State private var selectedTerminal: SystemTerminal?
    @State private var selectedHostTerminal: HostTerminal?
    @State private var showingNewTerminal = false
    @State private var pendingTerminal: SystemTerminal?

    enum ProcessMetric: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if let info = store.systemInfo {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        categoryContent(info)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .refreshable { await refresh(force: true) }
            } else if let error = store.systemInfoError {
                ScrollView {
                    EmptyState(
                        icon: "desktopcomputer.trianglebadge.exclamationmark",
                        title: "System information unavailable",
                        subtitle: error
                    )
                    .padding(16)
                }
            } else {
                ScrollView {
                    LoadingState(message: "Reading system information…")
                        .padding(16)
                }
            }
        }
        .mobileScreenBackground()
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refresh(force: true) }
                } label: {
                    if store.isRefreshingSystemInfo {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshingSystemInfo)
                .accessibilityLabel("Refresh \(category.title.lowercased())")
            }
        }
        .task { await refresh() }
        .sheet(item: $selectedTerminal) { terminal in
            if let api = store.api {
                MobileTerminalDetailView(terminal: terminal, api: api)
                    .environmentObject(store)
            }
        }
        .sheet(item: $selectedHostTerminal) { terminal in
            if let api = store.api {
                MobileHostTerminalDetailView(terminal: terminal, api: api)
            }
        }
        .sheet(isPresented: $showingNewTerminal, onDismiss: openPendingTerminal) {
            MobileNewTerminalSheet(directory: store.orderedProjects.first?.canonical) { terminal in
                pendingTerminal = terminal
            }
            .environmentObject(store)
        }
    }

    private func refresh(force: Bool = false) async {
        async let system: Void = store.refreshSystemInfo(force: force)
        async let terminals: Void = store.refreshTerminals(force: force)
        async let hostTerminals: Void = store.refreshHostTerminals(force: force)
        _ = await (system, terminals, hostTerminals)
    }

    /// Opening the detail page from the new-terminal sheet's `onDismiss` avoids
    /// presenting two sheets in the same run loop.
    private func openPendingTerminal() {
        guard let terminal = pendingTerminal else { return }
        pendingTerminal = nil
        selectedTerminal = terminal
    }

    @ViewBuilder
    private func categoryContent(_ info: SystemInfo) -> some View {
        switch category {
        case .performance:
            cpuSection(info)
            memorySection(info)
            processesSection(info)
        case .storage:
            disksSection(info)
        case .network:
            networkSection(info)
            portsSection(info)
        case .software:
            homebrewSection(info)
            appsSection(info)
            runtimesSection(info)
            dockerSection(info)
        case .health:
            powerSection(info)
        case .machine:
            hostSection(info)
            displaysSection(info)
            hubSection(info)
        case .terminals:
            terminalsSection
            hostTerminalsSection
        case .files:
            filesSection(info)
        }
    }

    // MARK: - Terminals

    private var hostTerminalsSection: some View {
        MobileHostTerminalsSection { terminal in
            selectedHostTerminal = terminal
        }
    }

    private var terminalsSection: some View {
        MobileTerminalsSection(
            onOpen: { terminal in selectedTerminal = terminal },
            onNew: { showingNewTerminal = true }
        )
    }

    // MARK: - Files

    private func filesSection(_ info: SystemInfo) -> some View {
        let home = info.host.home ?? "~"
        var quickLinks = [
            HostFileRoot(name: "Home", path: home, kind: "home"),
            HostFileRoot(name: "Root", path: "/", kind: "root"),
        ]
        if info.platformName == "macOS" {
            quickLinks.append(HostFileRoot(name: "Applications", path: "/Applications", kind: "applications"))
            quickLinks.append(HostFileRoot(name: "Volumes", path: "/Volumes", kind: "volumes"))
        }
        let projects = Array(store.orderedProjects.prefix(8))

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Files")
            VStack(alignment: .leading, spacing: 10) {
                Text("Browse folders on the Mac running the hub. Text and images open read-only; nothing can be edited or deleted here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(quickLinks) { root in
                            NavigationLink {
                                MobileFileBrowserView(startPath: root.path)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: root.icon)
                                        .font(.caption2.weight(.semibold))
                                    Text(root.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !projects.isEmpty {
                    Divider().opacity(0.5)
                    Text("PROJECTS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(projects) { project in
                                NavigationLink {
                                    MobileFileBrowserView(startPath: project.canonical)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "folder")
                                            .font(.caption2.weight(.semibold))
                                        Text(project.displayName)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Machine

    private func hostSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Machine")
            VStack(alignment: .leading, spacing: 9) {
                MobileSystemRow("Name", info.host.name)
                MobileSystemRow("Hostname", info.host.hostname, monospaced: true)
                MobileSystemRow("OS", MobileSystemFormat.osLabel(info.host))
                MobileSystemRow("Kernel", info.host.kernel, monospaced: true)
                MobileSystemRow("Architecture", info.host.arch)
                if let model = info.host.model {
                    MobileSystemRow("Model", model)
                }
                if let chip = info.host.chip {
                    MobileSystemRow("Chip", chip)
                }
                if let booted = info.host.bootedDate {
                    MobileSystemRow("Booted", booted.formatted(date: .abbreviated, time: .shortened))
                }
                if let user = info.host.username {
                    MobileSystemRow("User", user, monospaced: true)
                }
                if let shell = info.host.shell {
                    MobileSystemRow("Shell", shell, monospaced: true)
                }
                if let timezone = info.host.timezone {
                    MobileSystemRow("Timezone", timezone)
                }
                if info.host.isVirtualMachine == true {
                    MobileSystemRow("Virtual machine", info.host.virtualization ?? "yes", tint: Theme.warn)
                }
            }
            .card()
        }
    }

    // MARK: - CPU

    private func cpuSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Processor") {
                if let usage = info.cpu.usagePercent {
                    Text("\(Int(usage.rounded()))% used")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                if let model = info.cpu.model {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if let vendor = info.cpu.vendor {
                            Chip(text: vendor, tint: Theme.input)
                        }
                    }
                }
                if let usage = info.cpu.usagePercent {
                    MobileSystemBar(fraction: usage / 100, tint: Theme.input)
                }
                if let cores = info.cpu.perCoreUsage, !cores.isEmpty {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(cores.enumerated()), id: \.offset) { index, value in
                            ZStack(alignment: .bottom) {
                                Capsule().fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(Theme.input.opacity(0.35 + 0.65 * min(1, value / 100)))
                                    .frame(height: max(2, 30 * min(1, value / 100)))
                            }
                            .frame(height: 30)
                            .accessibilityLabel("Core \(index + 1)")
                            .accessibilityValue("\(Int(value.rounded())) percent")
                        }
                    }
                }
                HStack(spacing: 18) {
                    if let physical = info.cpu.physicalCores {
                        metric("Cores", "\(physical) / \(info.cpu.logicalCores)")
                    } else {
                        metric("Logical cores", "\(info.cpu.logicalCores)")
                    }
                    if let speed = info.cpu.speedMHz {
                        metric("Clock", "\(speed) MHz")
                    }
                    if let temperature = info.cpu.temperatureC {
                        metric("Temp", String(format: "%.1f°C", temperature))
                    }
                }
                if let load = info.cpu.loadAverage, !load.isEmpty {
                    HStack(spacing: 16) {
                        metric("Load 1m", String(format: "%.2f", load[0]))
                        if load.count > 1 { metric("5m", String(format: "%.2f", load[1])) }
                        if load.count > 2 { metric("15m", String(format: "%.2f", load[2])) }
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Memory

    private func memorySection(_ info: SystemInfo) -> some View {
        let memory = info.memory
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Memory") {
                Text("\(Fmt.bytes(memory.usedBytes)) / \(Fmt.bytes(memory.totalBytes))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 12) {
                MobileSystemBar(fraction: memory.usedFraction, tint: Theme.reasoning)
                HStack(spacing: 16) {
                    metric("Used", Fmt.bytes(memory.usedBytes))
                    metric("Free", Fmt.bytes(memory.freeBytes))
                    metric("Available", Fmt.bytes(memory.availableBytes ?? memory.freeBytes))
                }
                if memory.activeBytes != nil || memory.wiredBytes != nil || memory.compressedBytes != nil {
                    Divider().opacity(0.5)
                    HStack(spacing: 16) {
                        if let value = memory.activeBytes { metric("Active", Fmt.bytes(value)) }
                        if let value = memory.wiredBytes { metric("Wired", Fmt.bytes(value)) }
                        if let value = memory.compressedBytes { metric("Compressed", Fmt.bytes(value)) }
                    }
                }
                if let swapTotal = memory.swapTotalBytes, swapTotal > 0 {
                    HStack(spacing: 16) {
                        metric("Swap used", Fmt.bytes(memory.swapUsedBytes))
                        metric("Swap free", Fmt.bytes(memory.swapFreeBytes))
                        metric("Swap total", Fmt.bytes(swapTotal))
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Disks

    private func disksSection(_ info: SystemInfo) -> some View {
        let disks = showAllDisks ? info.disks : Array(info.disks.prefix(6))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Disks") {
                Text("\(info.disks.count) volumes")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(disks) { disk in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: disk.removable == true ? "externaldrive" : "internaldrive")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.cacheRead)
                            Text(disk.mount)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text("\(Fmt.bytes(disk.usedBytes)) of \(Fmt.bytes(disk.totalBytes))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        MobileSystemBar(
                            fraction: disk.usedFraction,
                            tint: disk.usedFraction > 0.9 ? Theme.danger : Theme.accent
                        )
                        HStack {
                            Text(disk.filesystem)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Fmt.bytes(disk.freeBytes)) free")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if info.disks.count > 6 {
                    Button(showAllDisks ? "Show fewer" : "Show all \(info.disks.count) volumes") {
                        showAllDisks.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
            .card()
        }
    }

    // MARK: - Network

    private func networkSection(_ info: SystemInfo) -> some View {
        let interfaces = info.network.interfaces.filter { interface in
            interface.addresses.contains { !$0.internal_ }
        }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Network") {
                if let name = info.network.defaultInterface {
                    Text(name)
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                MobileSystemRow("Hostname", info.network.hostname, monospaced: true)
                if let gateway = info.network.defaultGateway {
                    MobileSystemRow("Gateway", gateway, monospaced: true)
                }
                if !info.network.dnsServers.isEmpty {
                    MobileSystemRow("DNS", info.network.dnsServers.joined(separator: ", "), monospaced: true)
                }
                if !interfaces.isEmpty {
                    Divider().opacity(0.5)
                    ForEach(interfaces) { interface in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(interface.name)
                                    .font(.caption.monospaced().weight(.semibold))
                                Spacer(minLength: 4)
                                if let mac = interface.addresses.first(where: { $0.mac != nil })?.mac {
                                    Text(mac)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            ForEach(interface.addresses.filter { !$0.internal_ }, id: \.address) { address in
                                Text(address.cidr ?? address.address)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Power and security

    private func powerSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Power & Security")
            VStack(alignment: .leading, spacing: 10) {
                if let battery = info.battery, battery.present {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: battery.charging == true ? "battery.100percent.bolt" : "battery.75percent")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(MobileSystemFormat.batteryColor(battery))
                        Text("Battery")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        Text(battery.percent.map { "\($0)%" } ?? "—")
                            .font(.headline.weight(.semibold).monospacedDigit())
                    }
                    if let state = battery.state {
                        MobileSystemRow("State", state)
                    }
                    if let minutes = battery.minutesRemaining, minutes > 0 {
                        MobileSystemRow("Remaining", Fmt.uptime(minutes * 60))
                    }
                    if let health = battery.healthPercent {
                        MobileSystemRow("Health", "\(Int(health.rounded()))%", tint: health < 80 ? Theme.warn : Theme.accent)
                    }
                    if let cycles = battery.cycleCount {
                        MobileSystemRow("Cycles", "\(cycles)")
                    }
                    if let condition = battery.condition {
                        MobileSystemRow("Condition", condition)
                    }
                } else {
                    MobileSystemRow("Battery", "No battery", tint: .secondary)
                }

                if let thermal = info.thermal {
                    Divider().opacity(0.5)
                    MobileSystemRow("Thermal pressure", thermal.pressure ?? "—", tint: MobileSystemFormat.thermalPressureColor(thermal.pressure))
                    if let limit = thermal.cpuSpeedLimitPercent {
                        MobileSystemRow("CPU speed limit", "\(limit)%")
                    }
                    if let temperature = thermal.temperatureC {
                        MobileSystemRow("Temperature", String(format: "%.1f°C", temperature))
                    }
                }

                if let security = info.security {
                    Divider().opacity(0.5)
                    securityRow("SIP", security.systemIntegrityProtection)
                    securityRow("FileVault", security.fileVault)
                    securityRow("Firewall", security.firewall)
                    securityRow("Gatekeeper", security.gatekeeper)
                    securityRow("Secure Boot", security.secureBoot)
                    if let selinux = security.selinux {
                        MobileSystemRow("SELinux", selinux)
                    }
                    if let appArmor = security.appArmor {
                        MobileSystemRow("AppArmor", appArmor)
                    }
                    if let defender = security.defender {
                        MobileSystemRow("Defender", defender)
                    }
                }
            }
            .card()
        }
    }

    private func securityRow(_ label: String, _ flag: SystemFlag?) -> some View {
        MobileSystemRow(
            label,
            flag?.label ?? "—",
            tint: flag?.isEnabled == true ? Theme.accent : flag?.isEnabled == false ? Theme.warn : .secondary
        )
    }

    // MARK: - Processes

    private func processesSection(_ info: SystemInfo) -> some View {
        let processes = processMetric == .cpu ? info.processes.topCPU : info.processes.topMemory
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Processes") {
                Picker("Sort", selection: $processMetric) {
                    ForEach(ProcessMetric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 136)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("\(Fmt.grouped(info.processes.total)) total processes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(processMetric == .cpu ? "CPU" : "MEMORY")
                        .font(.caption2.weight(.bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                }
                ForEach(processes.prefix(10)) { process in
                    HStack(spacing: 8) {
                        Text(process.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(process.pid)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        Text(processValue(process))
                            .font(.caption2.monospaced().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .card()
        }
    }

    private func processValue(_ process: SystemProcess) -> String {
        if processMetric == .cpu {
            return process.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "—"
        }
        return Fmt.bytes(process.memoryBytes)
    }

    // MARK: - Homebrew

    private func homebrewSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Homebrew") {
                if let brew = info.homebrew, brew.available {
                    Text("\(brew.formulaCount) formulae · \(brew.caskCount) casks")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let brew = info.homebrew, brew.available {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        if let version = brew.version {
                            Chip(text: version, systemImage: "shippingbox", tint: Theme.cacheRead)
                        }
                        if brew.outdatedCount > 0 {
                            Chip(text: "\(brew.outdatedCount) outdated", systemImage: "arrow.up.circle", tint: Theme.warn)
                        } else {
                            Chip(text: "Up to date", systemImage: "checkmark.circle", tint: Theme.accent)
                        }
                    }
                    if let prefix = brew.prefix {
                        MobileSystemRow("Prefix", prefix, monospaced: true)
                    }
                    Divider().opacity(0.5)
                    let packages = sortedBrewPackages(brew.packages)
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(showAllBrew ? packages : Array(packages.prefix(12))) { package in
                            HStack(spacing: 8) {
                                Image(systemName: package.isCask ? "app.dashed" : "shippingbox")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(package.isCask ? Theme.reasoning : Theme.cacheRead)
                                Text(package.name)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if package.outdated {
                                    Circle()
                                        .fill(Theme.warn)
                                        .frame(width: 4, height: 4)
                                        .accessibilityLabel("Outdated")
                                }
                                Spacer(minLength: 4)
                                Text(package.version)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if packages.count > 12 {
                            Button(showAllBrew ? "Show fewer" : "Show all \(packages.count) packages") {
                                showAllBrew.toggle()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .card()
            } else {
                Text("Homebrew was not found on the hub's PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            }
        }
    }

    private func sortedBrewPackages(_ packages: [SystemBrewPackage]) -> [SystemBrewPackage] {
        packages.sorted { left, right in
            if left.outdated != right.outdated { return left.outdated }
            if left.kind != right.kind { return left.kind == "formula" }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    // MARK: - Apps

    private func appsSection(_ info: SystemInfo) -> some View {
        let matches = filteredApps(info.apps)
        let visible = showAllApps || !appQuery.isEmpty ? matches : Array(matches.prefix(10))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Installed Apps") {
                Text("\(info.apps.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    TextField("Filter applications", text: $appQuery)
                        .textFieldStyle(.plain)
                        .font(.caption)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                if matches.isEmpty {
                    Text(appQuery.isEmpty ? "No applications found." : "No apps match “\(appQuery)”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(visible) { app in
                            NavigationLink {
                                MobileSystemAppDetailView(app: app)
                            } label: {
                                HStack(spacing: 9) {
                                    AppIconView(
                                        api: store.api,
                                        path: app.path,
                                        hasIcon: app.hasIcon == true,
                                        size: 18
                                    )
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.name)
                                            .font(.caption.weight(.medium))
                                            .lineLimit(1)
                                        Text(app.path)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 4)
                                    if let version = app.version {
                                        Text(version)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if !showAllApps && appQuery.isEmpty && matches.count > 10 {
                            Button("Show all \(matches.count) applications") {
                                showAllApps = true
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                        } else if showAllApps && appQuery.isEmpty {
                            Button("Show fewer") {
                                showAllApps = false
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .card()
        }
    }

    private func filteredApps(_ apps: [SystemApp]) -> [SystemApp] {
        let query = appQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleID?.localizedCaseInsensitiveContains(query) ?? false)
                || $0.path.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Tools, ports, docker, displays, hub

    private func runtimesSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Developer Tools") {
                Text("\(info.runtimes.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if info.runtimes.isEmpty {
                Text("No developer tools were found on the hub's PATH.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(info.runtimes) { runtime in
                        HStack(spacing: 8) {
                            Image(systemName: runtime.kind == "runtime" ? "terminal" : "wrench.and.screwdriver")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(runtime.kind == "runtime" ? Theme.accent : Theme.cacheRead)
                                .frame(width: 14)
                            Text(runtime.name)
                                .font(.caption.weight(.medium))
                            Spacer(minLength: 4)
                            Text(runtime.version ?? "installed")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .card()
            }
        }
    }

    private func portsSection(_ info: SystemInfo) -> some View {
        let ports = showAllPorts ? info.listeningPorts : Array(info.listeningPorts.prefix(12))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Listening Ports") {
                Text("\(info.listeningPorts.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if info.listeningPorts.isEmpty {
                Text("No listening TCP ports reported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(ports) { port in
                        HStack(spacing: 8) {
                            Text(":\(port.port)")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(Theme.running)
                                .frame(width: 52, alignment: .leading)
                            Text(port.process ?? "unknown")
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(port.address ?? "*")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            if let pid = port.pid {
                                Text("\(pid)")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if info.listeningPorts.count > 12 {
                        Button(showAllPorts ? "Show fewer" : "Show all \(info.listeningPorts.count) ports") {
                            showAllPorts.toggle()
                        }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
                .card()
            }
        }
    }

    @ViewBuilder
    private func dockerSection(_ info: SystemInfo) -> some View {
        if let docker = info.docker {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Docker") {
                    Chip(
                        text: docker.available ? "\(docker.running) running" : "daemon stopped",
                        systemImage: "shippingbox",
                        tint: docker.available ? Theme.accent : Theme.warn
                    )
                }
                VStack(alignment: .leading, spacing: 9) {
                    if let version = docker.version {
                        MobileSystemRow("Version", version)
                    }
                    if docker.containers.isEmpty {
                        Text(docker.available ? "No containers." : "Docker is installed, but the daemon is not reachable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(docker.containers) { container in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(container.state.lowercased() == "running" ? Theme.accent : Color.secondary.opacity(0.5))
                                    .frame(width: 5, height: 5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(container.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    Text(container.image)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(container.status)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    @ViewBuilder
    private func displaysSection(_ info: SystemInfo) -> some View {
        if !info.displays.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Displays")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(info.displays) { group in
                        HStack(spacing: 6) {
                            Text(group.name)
                                .font(.caption.weight(.semibold))
                            if let cores = group.cores {
                                Text("\(cores)-core GPU")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 4)
                            if let vendor = group.vendor {
                                Chip(text: vendor, tint: Theme.reasoning)
                            }
                        }
                        ForEach(group.displays) { display in
                            HStack(spacing: 8) {
                                Image(systemName: display.main == true ? "display" : "display.2")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accent)
                                Text(display.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(display.resolution ?? display.pixels ?? "—")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    private func hubSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Hub Process")
            VStack(alignment: .leading, spacing: 9) {
                MobileSystemRow("Version", info.hub.version)
                MobileSystemRow("PID", "\(info.hub.pid)", monospaced: true)
                MobileSystemRow("Runtime", "\(info.hub.runtime) \(info.hub.runtimeVersion)")
                MobileSystemRow("Uptime", Fmt.uptime(info.hub.uptime))
                if let port = info.hub.port {
                    MobileSystemRow("Port", "\(port)", monospaced: true)
                }
                if let rss = info.hub.rssBytes {
                    MobileSystemRow("Memory", Fmt.bytes(rss))
                }
                if let path = info.hub.dbPath {
                    MobileSystemRow("Database", path, monospaced: true, tint: .secondary)
                }
                if let size = info.hub.dbSizeBytes {
                    MobileSystemRow("Database size", Fmt.bytes(size))
                }
            }
            .card()
        }
    }

    // MARK: - Helpers

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}
