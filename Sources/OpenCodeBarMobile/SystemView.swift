import SwiftUI

/// Landing page for the Mac running the hub. The long inventory lives in
/// focused category pages (`MobileSystemCategoryView`); this screen stays short
/// and answers "how is the host doing right now?" at a glance.
struct SystemView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore

    @State private var volumeDraft: Double = 0
    @State private var adjustingVolume = false
    /// Debug/screenshot hook: `OPENCODEBAR_FILES=<path>` opens the host file
    /// browser directly on launch.
    @State private var debugFilesPath: String? = ProcessInfo.processInfo.environment["OPENCODEBAR_FILES"]
    /// Debug/screenshot hook: `OPENCODEBAR_SYSTEM_CATEGORY=<name>` opens one
    /// System category directly on launch.
    @State private var debugCategory: MobileSystemCategory? = {
        #if DEBUG
        ProcessInfo.processInfo.environment["OPENCODEBAR_SYSTEM_CATEGORY"]
            .flatMap(MobileSystemCategory.init(rawValue:))
        #else
        nil
        #endif
    }()

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
        .navigationDestination(item: $debugCategory) { category in
            MobileSystemCategoryView(category: category)
        }
        .task { await poll() }
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
                    exploreSection(info)
                    mediaSection(info)
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

    // MARK: - Overview

    private func overview(_ info: SystemInfo) -> some View {
        let rootDisk = info.disks.first(where: { $0.mount == "/" }) ?? info.disks.first
        let load = info.cpu.loadAverage?.first
        let cpuValue = info.cpu.usagePercent.map { "\(Int($0.rounded()))%" }
            ?? load.map { String(format: "%.2f", $0) }
            ?? "—"
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            NavigationLink {
                MobileSystemCategoryView(category: .machine)
            } label: {
                MobileSystemTile(
                    icon: "desktopcomputer",
                    tint: Theme.accent,
                    label: "System",
                    value: info.platformName,
                    caption: [info.host.osName, info.host.osVersion].compactMap { $0 }.joined(separator: " "),
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MobileSystemCategoryView(category: .machine)
            } label: {
                MobileSystemTile(
                    icon: "clock",
                    tint: Theme.running,
                    label: "Uptime",
                    value: Fmt.uptime(info.host.uptime),
                    caption: info.host.bootedDate.map { "since \(Fmt.relative(from: $0))" },
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)

            NavigationLink {
                MobileSystemCategoryView(category: .performance)
            } label: {
                MobileSystemTile(
                    icon: "cpu",
                    tint: Theme.input,
                    label: "CPU",
                    value: cpuValue,
                    caption: "\(info.cpu.logicalCores) cores",
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)

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

            NavigationLink {
                MobileSystemCategoryView(category: .storage)
            } label: {
                MobileSystemTile(
                    icon: "internaldrive",
                    tint: Theme.cacheRead,
                    label: "Disk free",
                    value: Fmt.bytes(rootDisk?.freeBytes),
                    caption: rootDisk?.mount ?? "No disk reported",
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)

            if let battery = info.battery, battery.present {
                NavigationLink {
                    MobileSystemCategoryView(category: .health)
                } label: {
                    MobileSystemTile(
                        icon: "battery.75percent",
                        tint: MobileSystemFormat.batteryColor(battery),
                        label: "Battery",
                        value: battery.percent.map { "\($0)%" } ?? "—",
                        caption: battery.state ?? (battery.charging == true ? "Charging" : "On battery"),
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink {
                    MobileSystemCategoryView(category: .performance)
                } label: {
                    MobileSystemTile(
                        icon: "list.bullet.rectangle",
                        tint: Theme.output,
                        label: "Processes",
                        value: Fmt.grouped(info.processes.total),
                        caption: "\(info.listeningPorts.count) listening ports",
                        showsDisclosure: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Explore

    private func exploreSection(_ info: SystemInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Explore") {
                Text("\(MobileSystemCategory.allCases.count) sections")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(MobileSystemCategory.allCases) { category in
                    NavigationLink {
                        MobileSystemCategoryView(category: category)
                    } label: {
                        MobileSystemNavTile(
                            icon: category.icon,
                            tint: category.tint,
                            title: category.title,
                            caption: category.caption(info: info, store: store)
                        )
                    }
                    .buttonStyle(.plain)
                }
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
}
