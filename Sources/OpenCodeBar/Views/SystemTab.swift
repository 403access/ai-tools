import SwiftUI

/// Everything the hub can learn about the machine it runs on. The tab polls the
/// snapshot every few seconds; expensive sections (apps, Homebrew, toolchains)
/// are cached by the hub rather than re-collected on every poll.
struct SystemTab: View {
    @EnvironmentObject var state: AppState

    @State private var processMetric: ProcessMetric = .cpu
    @State private var showAllDisks = false
    @State private var showAllApps = false
    @State private var appQuery = ""
    @State private var showAllBrew = false
    @State private var showAllPorts = false

    enum ProcessMetric: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let error = state.systemInfoError, state.systemInfo != nil {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            }

            if let info = state.systemInfo {
                overview(info)
                filesSection(info)
                hostSection(info)
                cpuSection(info)
                memorySection(info)
                disksSection(info)
                networkSection(info)
                powerSection(info)
                processesSection(info)
                homebrewSection(info)
                appsSection(info)
                runtimesSection(info)
                portsSection(info)
                dockerSection(info)
                displaysSection(info)
                hubSection(info)
                notesSection(info)
            } else if let error = state.systemInfoError {
                EmptyState(
                    icon: "desktopcomputer.trianglebadge.exclamationmark",
                    title: "System information unavailable",
                    subtitle: error
                )
            } else {
                loadingCard
            }
        }
        .task { await poll() }
    }

    private func poll() async {
        while !Task.isCancelled {
            await state.refreshSystemInfo()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    // MARK: - Header

    private var header: some View {
        SectionHeader("System") {
            HStack(spacing: 8) {
                if state.isRefreshingSystemInfo {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                }
                if let fetched = state.systemInfoFetchedAt {
                    Text("Updated \(Fmt.relative(from: fetched))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await state.refreshSystemInfo(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh system information")
            }
        }
    }

    private var loadingCard: some View {
        VStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text("Reading system information…")
                .font(.system(size: 11, weight: .medium))
            Text("The first request scans installed apps, Homebrew and developer tools. Later refreshes reuse that cache.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .card()
    }

    // MARK: - Overview

    private func overview(_ info: SystemInfo) -> some View {
        let rootDisk = info.disks.first(where: { $0.mount == "/" }) ?? info.disks.first
        let load = info.cpu.loadAverage?.first
        let cpuValue = info.cpu.usagePercent.map { "\(Int($0.rounded()))%" }
            ?? load.map { String(format: "%.2f", $0) }
            ?? "—"
        let cpuCaption = info.cpu.usagePercent == nil
            ? "load average · \(info.cpu.logicalCores) cores"
            : "\(info.cpu.logicalCores) cores"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            StatTile(
                icon: "desktopcomputer",
                tint: Theme.accent,
                label: "System",
                value: info.platformName,
                caption: [info.host.osName, info.host.osVersion].compactMap { $0 }.joined(separator: " ")
            )
            StatTile(
                icon: "clock",
                tint: Theme.running,
                label: "Uptime",
                value: Fmt.uptime(info.host.uptime),
                caption: info.host.bootedDate.map { "since \(Fmt.relative(from: $0))" }
            )
            StatTile(
                icon: "cpu",
                tint: Theme.input,
                label: "CPU",
                value: cpuValue,
                caption: cpuCaption
            )
            StatTile(
                icon: "memorychip",
                tint: Theme.reasoning,
                label: "Memory",
                value: Fmt.bytes(info.memory.usedBytes),
                caption: "of \(Fmt.bytes(info.memory.totalBytes))"
            )
            StatTile(
                icon: "internaldrive",
                tint: Theme.cacheRead,
                label: "Disk free",
                value: Fmt.bytes(rootDisk?.freeBytes),
                caption: rootDisk?.mount ?? "No disk reported"
            )
            if let battery = info.battery, battery.present {
                StatTile(
                    icon: "battery.75percent",
                    tint: batteryColor(battery),
                    label: "Battery",
                    value: battery.percent.map { "\($0)%" } ?? "—",
                    caption: battery.state ?? (battery.charging == true ? "Charging" : "On battery")
                )
            } else {
                StatTile(
                    icon: "list.bullet.rectangle",
                    tint: Theme.output,
                    label: "Processes",
                    value: Fmt.grouped(info.processes.total),
                    caption: "\(info.listeningPorts.count) listening ports"
                )
            }
        }
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
        let projects = Array(state.orderedProjects.prefix(8))

        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Files")
            VStack(alignment: .leading, spacing: 9) {
                Text("Browse folders on the machine running the hub. Text and images open in a read-only preview; nothing can be edited or deleted from here.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(quickLinks) { root in
                            Button {
                                state.openFileBrowser(at: root.path)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: root.icon)
                                        .font(.system(size: 8, weight: .semibold))
                                    Text(root.name)
                                        .font(.system(size: 9, weight: .medium))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                            }
                            .buttonStyle(.plain)
                            .help(root.path)
                        }
                    }
                }

                if !projects.isEmpty {
                    Divider().opacity(0.5)
                    Text("PROJECTS")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(projects) { project in
                                Button {
                                    state.openFileBrowser(at: project.canonical)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 8, weight: .semibold))
                                        Text(project.displayName)
                                            .font(.system(size: 9, weight: .medium))
                                            .lineLimit(1)
                                    }
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                                }
                                .buttonStyle(.plain)
                                .help(project.canonical)
                            }
                        }
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Host

    private func hostSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Machine")
            VStack(alignment: .leading, spacing: 8) {
                SystemInfoRow("Name", info.host.name)
                SystemInfoRow("Hostname", info.host.hostname, monospaced: true)
                SystemInfoRow("OS", osLabel(info.host))
                SystemInfoRow("Kernel", info.host.kernel, monospaced: true)
                SystemInfoRow("Architecture", info.host.arch)
                if let model = info.host.model {
                    SystemInfoRow("Model", model)
                }
                if let chip = info.host.chip {
                    SystemInfoRow("Chip", chip)
                }
                if let machine = info.host.machine, machine != info.host.model {
                    SystemInfoRow("Machine ID", machine, monospaced: true)
                }
                if let booted = info.host.bootedDate {
                    SystemInfoRow("Booted", booted.formatted(date: .abbreviated, time: .shortened))
                }
                if let user = info.host.username {
                    SystemInfoRow("User", user, monospaced: true)
                }
                if let shell = info.host.shell {
                    SystemInfoRow("Shell", shell, monospaced: true)
                }
                if let timezone = info.host.timezone {
                    SystemInfoRow("Timezone", timezone)
                }
                if let locale = info.host.locale {
                    SystemInfoRow("Locale", locale, monospaced: true)
                }
                if info.host.isVirtualMachine == true {
                    SystemInfoRow("Virtual machine", info.host.virtualization ?? "yes", tint: Theme.warn)
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
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                if let model = info.cpu.model {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(model)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        if let vendor = info.cpu.vendor {
                            Chip(text: vendor, tint: Theme.input)
                        }
                    }
                }

                if let usage = info.cpu.usagePercent {
                    UsageBar(fraction: usage / 100, tint: Theme.input)
                }

                if let cores = info.cpu.perCoreUsage, !cores.isEmpty {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(Array(cores.enumerated()), id: \.offset) { index, value in
                            VStack(spacing: 3) {
                                ZStack(alignment: .bottom) {
                                    Capsule().fill(Color.primary.opacity(0.08))
                                    Capsule()
                                        .fill(Theme.input.opacity(0.35 + 0.65 * min(1, value / 100)))
                                        .frame(height: max(2, 22 * min(1, value / 100)))
                                }
                                .frame(height: 22)
                                .help("Core \(index + 1): \(Int(value.rounded()))%")
                            }
                        }
                    }
                }

                HStack(spacing: 14) {
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
                    HStack(spacing: 12) {
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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 10) {
                UsageBar(fraction: memory.usedFraction, tint: Theme.reasoning)
                HStack(spacing: 12) {
                    metric("Used", Fmt.bytes(memory.usedBytes))
                    metric("Free", Fmt.bytes(memory.freeBytes))
                    metric("Available", Fmt.bytes(memory.availableBytes ?? memory.freeBytes))
                }
                if memory.activeBytes != nil || memory.wiredBytes != nil || memory.compressedBytes != nil {
                    Divider().opacity(0.5)
                    HStack(spacing: 12) {
                        if let value = memory.activeBytes { metric("Active", Fmt.bytes(value)) }
                        if let value = memory.inactiveBytes { metric("Inactive", Fmt.bytes(value)) }
                        if let value = memory.wiredBytes { metric("Wired", Fmt.bytes(value)) }
                        if let value = memory.compressedBytes { metric("Compressed", Fmt.bytes(value)) }
                    }
                }
                if let swapTotal = memory.swapTotalBytes, swapTotal > 0 {
                    HStack(spacing: 12) {
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
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(disks) { disk in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: disk.removable == true ? "externaldrive" : "internaldrive")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.cacheRead)
                            Text(disk.mount)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 4)
                            Text("\(Fmt.bytes(disk.usedBytes)) of \(Fmt.bytes(disk.totalBytes))")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        UsageBar(fraction: disk.usedFraction, tint: disk.usedFraction > 0.9 ? Theme.danger : Theme.accent)
                        HStack(spacing: 6) {
                            Text(disk.filesystem)
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Fmt.bytes(disk.freeBytes)) free")
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if info.disks.count > 6 {
                    Button(showAllDisks ? "Show fewer" : "Show all \(info.disks.count) volumes") {
                        showAllDisks.toggle()
                    }
                    .font(.system(size: 10, weight: .semibold))
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
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SystemInfoRow("Hostname", info.network.hostname, monospaced: true)
                if let gateway = info.network.defaultGateway {
                    SystemInfoRow("Gateway", gateway, monospaced: true)
                }
                if !info.network.dnsServers.isEmpty {
                    SystemInfoRow("DNS", info.network.dnsServers.joined(separator: ", "), monospaced: true)
                }
                if !interfaces.isEmpty {
                    Divider().opacity(0.5)
                    ForEach(interfaces) { interface in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(interface.name)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                Spacer(minLength: 4)
                                if let mac = interface.addresses.first(where: { $0.mac != nil })?.mac {
                                    Text(mac)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            ForEach(interface.addresses.filter { !$0.internal_ }, id: \.address) { address in
                                Text(address.cidr ?? address.address)
                                    .font(.system(size: 9, design: .monospaced))
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

    // MARK: - Power, thermal and security

    private func powerSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Power & Security")
            VStack(alignment: .leading, spacing: 9) {
                if let battery = info.battery, battery.present {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: battery.charging == true ? "battery.100percent.bolt" : "battery.75percent")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(batteryColor(battery))
                        Text("Battery")
                            .font(.system(size: 11, weight: .semibold))
                        Spacer(minLength: 4)
                        Text(battery.percent.map { "\($0)%" } ?? "—")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    if let state = battery.state {
                        SystemInfoRow("State", state)
                    }
                    if let minutes = battery.minutesRemaining, minutes > 0 {
                        SystemInfoRow("Remaining", Fmt.uptime(minutes * 60))
                    }
                    if let health = battery.healthPercent {
                        SystemInfoRow("Health", "\(Int(health.rounded()))%", tint: health < 80 ? Theme.warn : Theme.accent)
                    }
                    if let cycles = battery.cycleCount {
                        SystemInfoRow("Cycles", "\(cycles)")
                    }
                    if let condition = battery.condition {
                        SystemInfoRow("Condition", condition)
                    }
                } else {
                    SystemInfoRow("Battery", "No battery", tint: .secondary)
                }

                if let thermal = info.thermal {
                    Divider().opacity(0.5)
                    SystemInfoRow("Thermal pressure", thermal.pressure ?? "—", tint: thermalPressureColor(thermal.pressure))
                    if let limit = thermal.cpuSpeedLimitPercent {
                        SystemInfoRow("CPU speed limit", "\(limit)%")
                    }
                    if let temperature = thermal.temperatureC {
                        SystemInfoRow("Temperature", String(format: "%.1f°C", temperature))
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
                        SystemInfoRow("SELinux", selinux)
                    }
                    if let appArmor = security.appArmor {
                        SystemInfoRow("AppArmor", appArmor)
                    }
                    if let defender = security.defender {
                        SystemInfoRow("Defender", defender)
                    }
                }
            }
            .card()
        }
    }

    private func securityRow(_ label: String, _ flag: SystemFlag?) -> some View {
        SystemInfoRow(
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
                .frame(width: 112)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Fmt.grouped(info.processes.total)) total processes")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(processMetric == .cpu ? "CPU" : "Memory")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                }
                ForEach(processes.prefix(10)) { process in
                    HStack(spacing: 7) {
                        Text(process.name)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(process.pid)")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        if let user = process.user {
                            Text(user)
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        Text(processValue(process))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .help(process.command ?? process.name)
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
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if let brew = info.homebrew, brew.available {
                VStack(alignment: .leading, spacing: 9) {
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
                        SystemInfoRow("Prefix", prefix, monospaced: true)
                    }
                    Divider().opacity(0.5)
                    let packages = sortedBrewPackages(brew.packages)
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(showAllBrew ? packages : Array(packages.prefix(12))) { package in
                            HStack(spacing: 7) {
                                Image(systemName: package.isCask ? "app.dashed" : "shippingbox")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(package.isCask ? Theme.reasoning : Theme.cacheRead)
                                Text(package.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                if package.outdated {
                                    Circle()
                                        .fill(Theme.warn)
                                        .frame(width: 4, height: 4)
                                        .help("Outdated")
                                }
                                Spacer(minLength: 4)
                                Text(package.version)
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if packages.count > 12 {
                            Button(showAllBrew ? "Show fewer" : "Show all \(packages.count) packages") {
                                showAllBrew.toggle()
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .card()
            } else {
                Text("Homebrew was not found on the hub's PATH.")
                    .font(.system(size: 10))
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

    // MARK: - Installed apps

    private func appsSection(_ info: SystemInfo) -> some View {
        let matches = filteredApps(info.apps)
        let visible = showAllApps || !appQuery.isEmpty ? matches : Array(matches.prefix(10))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Installed Apps") {
                Text("\(info.apps.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                    TextField("Filter applications", text: $appQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                if matches.isEmpty {
                    Text(appQuery.isEmpty ? "No applications found." : "No apps match “\(appQuery)”.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(visible) { app in
                            HStack(spacing: 8) {
                                Image(systemName: "app")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 14)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(app.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                    Text(app.sourceLabel)
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if let version = app.version {
                                    Text(version)
                                        .font(.system(size: 8.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .help(app.path)
                        }

                        if !showAllApps && appQuery.isEmpty && matches.count > 10 {
                            Button("Show all \(matches.count) applications") {
                                showAllApps = true
                            }
                            .font(.system(size: 10, weight: .semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                        } else if showAllApps && appQuery.isEmpty {
                            Button("Show fewer") {
                                showAllApps = false
                            }
                            .font(.system(size: 10, weight: .semibold))
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

    // MARK: - Developer tools

    private func runtimesSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Developer Tools") {
                Text("\(info.runtimes.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if info.runtimes.isEmpty {
                Text("No developer tools were found on the hub's PATH.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(info.runtimes) { runtime in
                        HStack(spacing: 7) {
                            Image(systemName: runtime.kind == "runtime" ? "terminal" : "wrench.and.screwdriver")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(runtime.kind == "runtime" ? Theme.accent : Theme.cacheRead)
                                .frame(width: 12)
                            Text(runtime.name)
                                .font(.system(size: 10, weight: .medium))
                            Spacer(minLength: 4)
                            Text(runtime.version ?? "installed")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .help(runtime.path ?? runtime.name)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Ports

    private func portsSection(_ info: SystemInfo) -> some View {
        let ports = showAllPorts ? info.listeningPorts : Array(info.listeningPorts.prefix(12))
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Listening Ports") {
                Text("\(info.listeningPorts.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            if info.listeningPorts.isEmpty {
                Text("No listening TCP ports reported.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(ports) { port in
                        HStack(spacing: 7) {
                            Text(":\(port.port)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.running)
                                .frame(width: 46, alignment: .leading)
                            Text(port.process ?? "unknown")
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(port.address ?? "*")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            if let pid = port.pid {
                                Text("\(pid)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    if info.listeningPorts.count > 12 {
                        Button(showAllPorts ? "Show fewer" : "Show all \(info.listeningPorts.count) ports") {
                            showAllPorts.toggle()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Docker

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
                VStack(alignment: .leading, spacing: 8) {
                    if let version = docker.version {
                        SystemInfoRow("Version", version)
                    }
                    if docker.containers.isEmpty {
                        Text(docker.available ? "No containers." : "Docker is installed, but the daemon is not reachable.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(docker.containers) { container in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(container.state.lowercased() == "running" ? Theme.accent : Color.secondary.opacity(0.5))
                                    .frame(width: 5, height: 5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(container.name)
                                        .font(.system(size: 10, weight: .medium))
                                        .lineLimit(1)
                                    Text(container.image)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Text(container.status)
                                    .font(.system(size: 8.5))
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

    // MARK: - Displays

    @ViewBuilder
    private func displaysSection(_ info: SystemInfo) -> some View {
        if !info.displays.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader("Displays")
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(info.displays) { group in
                        HStack(spacing: 6) {
                            Text(group.name)
                                .font(.system(size: 10, weight: .semibold))
                            if let cores = group.cores {
                                Text("\(cores)-core GPU")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer(minLength: 4)
                            if let vendor = group.vendor {
                                Chip(text: vendor, tint: Theme.reasoning)
                            }
                        }
                        ForEach(group.displays) { display in
                            HStack(spacing: 6) {
                                Image(systemName: display.main == true ? "display" : "display.2")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.accent)
                                Text(display.name)
                                    .font(.system(size: 10))
                                    .lineLimit(1)
                                Spacer(minLength: 4)
                                Text(display.resolution ?? display.pixels ?? "—")
                                    .font(.system(size: 8.5, design: .monospaced))
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

    // MARK: - Hub

    private func hubSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Hub Process")
            VStack(alignment: .leading, spacing: 8) {
                SystemInfoRow("Version", info.hub.version)
                SystemInfoRow("PID", "\(info.hub.pid)", monospaced: true)
                SystemInfoRow("Runtime", "\(info.hub.runtime) \(info.hub.runtimeVersion)")
                SystemInfoRow("Uptime", Fmt.uptime(info.hub.uptime))
                if let port = info.hub.port {
                    SystemInfoRow("Port", "\(port)", monospaced: true)
                }
                if let rss = info.hub.rssBytes {
                    SystemInfoRow("Memory", Fmt.bytes(rss))
                }
                if let path = info.hub.dbPath {
                    SystemInfoRow("Database", path, monospaced: true, tint: .secondary)
                }
                if let size = info.hub.dbSizeBytes {
                    SystemInfoRow("Database size", Fmt.bytes(size))
                }
                if let cwd = info.hub.cwd {
                    SystemInfoRow("Working dir", cwd, monospaced: true, tint: .secondary)
                }
            }
            .card()
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private func notesSection(_ info: SystemInfo) -> some View {
        if !info.notes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(info.notes, id: \.self) { note in
                    NoticeRow(icon: "info.circle", message: note, tint: Theme.warn)
                }
            }
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

    private func osLabel(_ host: SystemHost) -> String {
        var parts = [host.osName ?? host.platformName]
        if let version = host.osVersion { parts.append(version) }
        if let build = host.osBuild { parts.append("(\(build))") }
        return parts.joined(separator: " ")
    }

    private func batteryColor(_ battery: SystemBattery) -> Color {
        guard let percent = battery.percent else { return .secondary }
        if battery.charging == true { return Theme.accent }
        if percent <= 10 { return Theme.danger }
        if percent <= 25 { return Theme.warn }
        return Theme.accent
    }

    private func thermalPressureColor(_ pressure: String?) -> Color {
        switch pressure?.lowercased() {
        case "critical": return Theme.danger
        case "serious": return Theme.warn
        case "fair": return Theme.cacheRead
        default: return Theme.accent
        }
    }
}

// MARK: - Shared pieces

private struct SystemInfoRow: View {
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
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .system(size: 9, design: .monospaced) : .system(size: 10, weight: .medium))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct UsageBar: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: height)
    }
}

private extension SystemApp {
    var sourceLabel: String {
        guard let source, !source.isEmpty else { return path.isEmpty ? "Application" : path }
        switch source.lowercased() {
        case "apple": return "Apple · \(path)"
        case "mac_app_store": return "Mac App Store · \(path)"
        case "identified_developer": return "Developer · \(path)"
        default: return "\(source) · \(path)"
        }
    }
}
