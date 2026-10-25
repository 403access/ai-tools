import SwiftUI

/// Full health and inventory view for the Mac running the hub. Mirrors the Mac
/// panel's System tab with touch-sized rows and its own polling loop, so the
/// phone can monitor the machine without keeping the Mac app open.
struct SystemView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore

    @State private var processMetric: ProcessMetric = .cpu
    @State private var showAllDisks = false
    @State private var showAllApps = false
    @State private var appQuery = ""
    @State private var showAllBrew = false
    @State private var showAllPorts = false
    @State private var volumeDraft: Double = 0
    @State private var adjustingVolume = false
    @State private var selectedTerminal: SystemTerminal?
    @State private var selectedHostTerminal: HostTerminal?
    @State private var showingNewTerminal = false
    @State private var pendingTerminal: SystemTerminal?
    /// Debug/screenshot hook: `OPENCODEBAR_FILES=<path>` opens the host file
    /// browser directly on launch.
    @State private var debugFilesPath: String? = ProcessInfo.processInfo.environment["OPENCODEBAR_FILES"]

    enum ProcessMetric: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if !settings.isConfigured {
                ScrollView {
                    SetupPrompt(
                        title: "Connect to your Mac",
                        message: "Pair with the hub on your Mac to see its CPU, memory, disks, apps and Homebrew packages from here."
                    )
                    .padding(16)
                }
            } else {
                content
            }
        }
        .mobileScreenBackground()
        .navigationTitle("System")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await refreshAll(force: true) }
                } label: {
                    if store.isRefreshingSystemInfo {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.isRefreshingSystemInfo)
                .accessibilityLabel("Refresh system information")
            }
        }
        .refreshable { await refreshAll(force: true) }
        .navigationDestination(item: $debugFilesPath) { path in
            MobileFileBrowserView(startPath: path)
        }
        .task { await poll() }
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

    private func poll() async {
        while !Task.isCancelled {
            if !store.isPaused {
                await refreshAll()
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func refreshAll(force: Bool = false) async {
        async let system: Void = store.refreshSystemInfo(force: force)
        async let terminals: Void = store.refreshTerminals(force: force)
        async let hostTerminals: Void = store.refreshHostTerminals(force: force)
        _ = await (system, terminals, hostTerminals)
    }

    @ViewBuilder
    private var content: some View {
        if let info = store.systemInfo {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let error = store.systemInfoError {
                        NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                    }

                    overview(info)
                    mediaSection(info)
                    if info.platformName == "macOS" {
                        hostTerminalsSection
                    }
                    terminalsSection
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
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

    private func openPendingTerminal() {
        guard let terminal = pendingTerminal else { return }
        pendingTerminal = nil
        selectedTerminal = terminal
    }

    // MARK: - Overview

    private func overview(_ info: SystemInfo) -> some View {
        let rootDisk = info.disks.first(where: { $0.mount == "/" }) ?? info.disks.first
        let load = info.cpu.loadAverage?.first
        let cpuValue = info.cpu.usagePercent.map { "\(Int($0.rounded()))%" }
            ?? load.map { String(format: "%.2f", $0) }
            ?? "—"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MobileSystemTile(
                icon: "desktopcomputer",
                tint: Theme.accent,
                label: "System",
                value: info.platformName,
                caption: [info.host.osName, info.host.osVersion].compactMap { $0 }.joined(separator: " ")
            )
            MobileSystemTile(
                icon: "clock",
                tint: Theme.running,
                label: "Uptime",
                value: Fmt.uptime(info.host.uptime),
                caption: info.host.bootedDate.map { "since \(Fmt.relative(from: $0))" }
            )
            MobileSystemTile(
                icon: "cpu",
                tint: Theme.input,
                label: "CPU",
                value: cpuValue,
                caption: "\(info.cpu.logicalCores) cores"
            )
            NavigationLink {
                MobileMemoryMonitorView()
            } label: {
                MobileSystemTile(
                    icon: "memorychip",
                    tint: Theme.reasoning,
                    label: "Memory",
                    value: Fmt.bytes(info.memory.usedBytes),
                    caption: "of \(Fmt.bytes(info.memory.totalBytes))",
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens memory details and top processes")
            MobileSystemTile(
                icon: "internaldrive",
                tint: Theme.cacheRead,
                label: "Disk free",
                value: Fmt.bytes(rootDisk?.freeBytes),
                caption: rootDisk?.mount ?? "No disk reported"
            )
            if let battery = info.battery, battery.present {
                MobileSystemTile(
                    icon: "battery.75percent",
                    tint: batteryColor(battery),
                    label: "Battery",
                    value: battery.percent.map { "\($0)%" } ?? "—",
                    caption: battery.state ?? (battery.charging == true ? "Charging" : "On battery")
                )
            } else {
                MobileSystemTile(
                    icon: "list.bullet.rectangle",
                    tint: Theme.output,
                    label: "Processes",
                    value: Fmt.grouped(info.processes.total),
                    caption: "\(info.listeningPorts.count) listening ports"
                )
            }
        }
    }

    // MARK: - Media

    private func mediaSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Media") {
                if !info.media.isEmpty {
                    Text("\(info.media.count) active")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                if info.media.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "play.slash")
                            .font(.title3.weight(.light))
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nothing playing")
                                .font(.caption.weight(.medium))
                            Text("Media played in any app appears here with its title and player.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(Array(info.media.enumerated()), id: \.element.id) { index, media in
                        mediaRow(media, showControls: index == 0)
                    }
                }

                if let audio = info.audio, audio.controllable {
                    Divider().opacity(0.5)
                    volumeRow(audio)
                }

                if let error = store.mediaControlError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
        .onAppear { volumeDraft = Double(info.audio?.volumePercent ?? 0) }
        .onChange(of: info.audio?.volumePercent) { _, value in
            if !adjustingVolume {
                volumeDraft = Double(value ?? 0)
            }
        }
    }

    private func mediaRow(_ media: SystemMedia, showControls: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: media.kindIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(media.isPlaying ? Theme.accent : Theme.warn)
                    .frame(width: 20)

                Text(media.app)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Chip(
                    text: media.stateLabel,
                    systemImage: media.isPlaying ? "play.fill" : "pause.fill",
                    tint: media.isPlaying ? Theme.accent : Theme.warn
                )
            }

            if let title = media.title {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
            } else {
                Text(media.kind == "video" ? "Video playback detected" : "Audio playback detected")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let subtitle = mediaSubtitle(media) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let progress = media.progress {
                MobileSystemBar(fraction: progress, tint: media.isPlaying ? Theme.accent : Theme.warn, height: 5)
                HStack(spacing: 4) {
                    Text(mediaTime(media.elapsedSeconds))
                    Text("·")
                    Text(mediaTime(media.durationSeconds))
                    Spacer(minLength: 4)
                    if let kind = media.kind {
                        Text(kind.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .monospacedDigit()
            } else if let kind = media.kind {
                Text("Detected from the system \(kind) session")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if showControls && media.canControl {
                HStack(spacing: 8) {
                    if media.supportsPrevious {
                        mediaButton("backward.fill", help: "Previous") {
                            Task { await store.controlMedia("previous") }
                        }
                    }
                    if media.supportsSkipBack {
                        mediaButton("gobackward.15", help: "Back 15 seconds") {
                            Task { await store.controlMedia("back15") }
                        }
                    }
                    if media.supportsToggle {
                        mediaButton(media.isPlaying ? "pause.fill" : "play.fill", help: media.isPlaying ? "Pause" : "Play") {
                            Task { await store.controlMedia("toggle") }
                        }
                    }
                    if media.supportsSkipForward {
                        mediaButton("goforward.15", help: "Forward 15 seconds") {
                            Task { await store.controlMedia("forward15") }
                        }
                    }
                    if media.supportsNext {
                        mediaButton("forward.fill", help: "Next") {
                            Task { await store.controlMedia("next") }
                        }
                    }

                    if store.isControllingMedia {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    }

                    Spacer(minLength: 4)

                    Text("Controls target \(media.app)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.top, 2)
            }
        }
    }

    private func volumeRow(_ audio: SystemAudio) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    Task { await store.controlMedia("mute", value: audio.muted == true ? 0 : 1) }
                } label: {
                    Image(systemName: audio.muted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(audio.muted == true ? Theme.warn : Theme.accent)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isControllingMedia)
                .accessibilityLabel(audio.muted == true ? "Unmute" : "Mute")

                Slider(
                    value: Binding(
                        get: { volumeDraft },
                        set: { volumeDraft = $0 }
                    ),
                    in: 0...100,
                    onEditingChanged: { editing in
                        adjustingVolume = editing
                        if !editing {
                            Task { await store.controlMedia("volume", value: volumeDraft) }
                        }
                    }
                )
                .disabled(store.isControllingMedia)
                .tint(Theme.accent)

                Text("\(Int(volumeDraft.rounded()))%")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
            Text("SYSTEM OUTPUT VOLUME")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
        }
    }

    private func mediaButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 30)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.isControllingMedia)
        .accessibilityLabel(help)
    }

    private func mediaSubtitle(_ media: SystemMedia) -> String? {
        let parts = [media.artist, media.album].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func mediaTime(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
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
                MobileSystemRow("OS", osLabel(info.host))
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
                            .foregroundStyle(batteryColor(battery))
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
                    MobileSystemRow("Thermal pressure", thermal.pressure ?? "—", tint: thermalPressureColor(thermal.pressure))
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
                            }
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

// MARK: - Pieces

private struct MobileSystemTile: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    var caption: String?
    var showsDisclosure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if showsDisclosure {
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .card(padding: 11)
    }
}

private struct MobileSystemRow: View {
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
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .caption.weight(.medium))
                .foregroundStyle(tint == .secondary ? Color.primary : tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

struct MobileSystemBar: View {
    let fraction: Double
    var tint: Color = Theme.accent
    var height: CGFloat = 6

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
