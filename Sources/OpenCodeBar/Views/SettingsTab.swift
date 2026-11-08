import AppKit
import SwiftUI

/// Hub settings: who is connected, what the server is doing, and the controls
/// needed to manage it. Pairing lives here too so a new phone can be added
/// without opening a terminal.
struct SettingsTab: View {
    @EnvironmentObject var state: AppState
    /// Set by the desktop window to the exact width of the scroll content.
    /// The fallback measurement serves the menu bar panel.
    @Environment(\.settingsAvailableWidth) private var availableWidth: CGFloat?

    @State var copiedPairingLink = false
    @State private var showRestartConfirmation = false
    @State private var contentWidth: CGFloat = 0
    @AppStorage("tasks.projectIcons") private var showsProjectIcons = true
    @AppStorage(HubLauncher.directoryDefaultsKey) private var hubDirectory = ""

    private var layoutWidth: CGFloat { availableWidth ?? contentWidth }

    /// Big desktop windows show the sections side by side instead of one very
    /// long column. The tray panel and split columns keep the single stack.
    private var columnCount: Int {
        if layoutWidth >= 1400 { return 3 }
        if layoutWidth >= 760 { return 2 }
        return 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = state.settingsError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            } else if let notice = state.settingsNotice {
                NoticeRow(icon: "checkmark.circle.fill", message: notice, tint: Theme.accent)
            }

            switch columnCount {
            case 3:
                HStack(alignment: .top, spacing: 14) {
                    column([.app, .power, .connection, .pairing])
                    column([.server, .agents, .updates, .devices])
                    column([.deployments, .developer])
                }
            case 2:
                HStack(alignment: .top, spacing: 14) {
                    column([.app, .power, .connection, .pairing, .deployments])
                    column([.server, .agents, .updates, .devices, .developer])
                }
            default:
                column([.app, .power, .server, .agents, .updates, .devices, .deployments, .pairing, .connection, .developer])
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(width: availableWidth, alignment: .topLeading)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SettingsWidthKey.self, value: proxy.size.width)
            }
        )
        .onPreferenceChange(SettingsWidthKey.self) { contentWidth = $0 }
        .task { await state.refreshSettings() }
        .alert("Restart the hub?", isPresented: $showRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart") {
                Task { await state.restartServer() }
            }
        } message: {
            Text("OpenCodeBar will briefly lose its connection while the hub process restarts. Mac and iOS apps reconnect automatically.")
        }
    }

    private enum SettingsSection: Hashable {
        case app, power, server, agents, updates, devices, deployments, pairing, connection, developer
    }

    private func column(_ sections: [SettingsSection]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections, id: \.self) { section in
                sectionView(section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func sectionView(_ section: SettingsSection) -> some View {
        switch section {
        case .app: appSection
        case .power: powerSection
        case .server: serverSection
        case .agents: agentsSection
        case .updates: updatesSection
        case .devices: devicesSection
        case .deployments: deploymentsSection
        case .pairing: pairingSection
        case .connection: connectionSection
        case .developer: SettingsDeveloperSection()
        }
    }

    // MARK: - App

    /// The menu bar panel is always available. This adds an optional full
    /// desktop window (with a Dock icon) that shares the same live state.
    var appSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("App")

            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { state.usesDesktopWindow },
                    set: { state.usesDesktopWindow = $0 }
                )) {
                    Text("Desktop window")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("Run OpenCodeBar as a desktop app alongside the menu bar item. A resizable window opens at launch, with a Dock icon and the same sessions, projects, and settings.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Toggle(isOn: $showsProjectIcons) {
                    Text("Project icons in Tasks")
                        .font(.system(size: 12, weight: .medium))
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                Text("Show each project's app icon in the Tasks board group headers. Projects without artwork keep the folder symbol.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    // MARK: - Power

    /// The hub can hold a power assertion so the Mac does not idle-sleep while
    /// a phone or tablet is connected. The display still turns off normally.
    var powerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Power")

            VStack(alignment: .leading, spacing: 8) {
                if let settings = state.serverSettings,
                   settings.preventSleepSupported == true {
                    Toggle(isOn: Binding(
                        get: { state.serverSettings?.preventSleep ?? false },
                        set: { value in
                            Task { await state.updatePreventSleep(value) }
                        }
                    )) {
                        Text("Keep Mac awake")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(state.isUpdatingSettings)

                    Text(settings.preventSleep == true
                         ? "Idle sleep is blocked while the hub runs, so the phone and tablet keep their connection. The display can still turn off."
                         : "The Mac can sleep normally. Phones and tablets lose their connection while it is asleep.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if state.serverSettings?.preventSleepSupported == false {
                    Text("This hub is not running on macOS, so there is no host sleep to manage.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Sleep settings load from the hub. Connect to the hub to manage them.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    // MARK: - Server

    var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Server") {
                HStack(spacing: 6) {
                    if state.isRefreshingSettings {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    }
                    Circle()
                        .fill(serverOnline ? Theme.accent : Theme.danger)
                        .frame(width: 6, height: 6)
                    Text(serverOnline ? "Online" : "Offline")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(serverOnline ? Theme.accent : Theme.danger)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                serverRow("Version", serverHealth?.version ?? state.hubInfo?.version ?? "—")
                if let address = state.hubLocation?.url.absoluteString {
                    serverRow("Address", address, monospaced: true)
                }
                if let uptime = serverHealth?.uptime {
                    serverRow("Uptime", duration(seconds: uptime))
                }
                serverRow("OpenCode", opencodeLabel)
                if let cached = cachedLabel {
                    serverRow("Cached", cached)
                }
                if let lastSync = state.hubHealth?.opencode?.lastSync {
                    serverRow("Last sync", Fmt.relative(from: Date(timeIntervalSince1970: lastSync / 1000)))
                }
                if let db = serverHealth?.db {
                    serverRow("Database", (db as NSString).abbreviatingWithTildeInPath, monospaced: true, lineLimit: 2)
                }

                Divider().opacity(0.5)

                if serverOnline {
                    HStack(spacing: 8) {
                        Button {
                            Task { await state.syncNow() }
                        } label: {
                            Label(state.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isSyncing)

                        Button {
                            showRestartConfirmation = true
                        } label: {
                            Label(state.isRestartingServer ? "Restarting…" : "Restart", systemImage: "power")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(state.isRestartingServer || state.hubHealth == nil)
                    }
                } else {
                    startServerControls
                }

                HStack(spacing: 8) {
                    Button {
                        revealServerFiles()
                    } label: {
                        Label("Show files", systemImage: "folder")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await state.refreshSettings(force: true) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isRefreshingSettings)
                }
            }
            .card()
        }
    }

    /// Shown instead of the online controls when the hub is not answering.
    /// Starting it from here keeps the terminal out of the normal setup path.
    var startServerControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let remote = remoteHubURL {
                Text("This app is configured for a hub at \(remote.absoluteString). Start that hub, or remove the URL override in ~/.config/opencode/opencodebar.json.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The hub is not running. Start it here, or run make hub in the repository.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if serverDirectory == nil {
                    Button {
                        chooseServerDirectory()
                    } label: {
                        Label("Choose server folder", systemImage: "folder")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        Task { await state.startServer() }
                    } label: {
                        Label(state.isStartingServer ? "Starting…" : "Start server", systemImage: "play.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.isStartingServer)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Server folder")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Text(serverDirectoryLabel)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(serverDirectory == nil ? .tertiary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Button("Choose…") {
                        chooseServerDirectory()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if serverDirectory == nil {
                    Text("Choose the ai-tools checkout that contains the server folder. The app remembers it for next time.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if FileManager.default.fileExists(atPath: HubLauncher.logFileURL.path) {
                Button {
                    revealHubLog()
                } label: {
                    Label("Show hub log", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.link)
            }
        }
    }

    func chooseServerDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the ai-tools checkout that contains the server folder."
        if let server = serverDirectory {
            panel.directoryURL = server.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        hubDirectory = url.path
        state.settingsError = nil
    }

    // MARK: - Agents

    /// Caps how many sessions can run an agent turn at once. Prompts that
    /// arrive while every slot is busy wait in the task board's Queued column.
    var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Agents") {
                if state.isUpdatingSettings {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                if let settings = state.serverSettings {
                    let minimum = settings.maxConcurrentAgentsMin ?? 0
                    let maximum = settings.maxConcurrentAgentsMax ?? 16
                    HStack(spacing: 8) {
                        Text("Concurrent agents")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Stepper(
                            value: Binding(
                                get: { state.serverSettings?.maxConcurrentAgents ?? 0 },
                                set: { value in
                                    Task { await state.updateMaxConcurrentAgents(value) }
                                }
                            ),
                            in: minimum...maximum
                        ) {
                            Text(concurrencyLabel(settings.maxConcurrentAgents ?? 0))
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .frame(minWidth: 68, alignment: .trailing)
                        }
                        .disabled(state.isUpdatingSettings)
                    }

                    Text(settings.maxConcurrentAgents == 0
                         ? "No limit. Every prompt starts immediately."
                         : "New prompts wait in Queued until one of the \(settings.maxConcurrentAgents ?? 0) slots frees.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Agent settings load from the hub. Connect to the hub to manage them.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    func concurrencyLabel(_ count: Int) -> String {
        count == 0 ? "Unlimited" : "\(count)"
    }

    // MARK: - Updates

    var updatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Updates") {
                if state.isUpdatingSettings {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Streaming sessions can emit many events per second. The hub batches updates for the Mac and phone apps before forwarding them, which keeps the connection quieter while a session runs.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let settings = state.serverSettings {
                    HStack(spacing: 8) {
                        Text("Throttle")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)

                        Picker("Throttle", selection: throttleBinding) {
                            ForEach(throttleOptions, id: \.self) { value in
                                Text(throttleLabel(value)).tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 96)
                        .disabled(state.isUpdatingSettings)
                    }

                    Text(settings.eventThrottleMs == 0
                         ? "Every event is forwarded as it arrives."
                         : "Updates are delivered at most once every \(throttleLabel(settings.eventThrottleMs)). Higher values reduce traffic but make live rows slightly less immediate.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Update settings are unavailable on this hub.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    var throttleBinding: Binding<Int> {
        Binding(
            get: { state.serverSettings?.eventThrottleMs ?? 0 },
            set: { value in
                Task { await state.updateEventThrottle(value) }
            }
        )
    }

    var throttleOptions: [Int] {
        var values = [0, 100, 250, 500, 1_000, 2_000]
        if let current = state.serverSettings?.eventThrottleMs, !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values
    }

    func throttleLabel(_ milliseconds: Int) -> String {
        if milliseconds == 0 { return "Off" }
        if milliseconds % 1_000 == 0 { return "\(milliseconds / 1_000) s" }
        return "\(milliseconds) ms"
    }

    // MARK: - Devices

    var devicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Devices") {
                Text(deviceCountLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if state.devices.isEmpty {
                EmptyState(
                    icon: "desktopcomputer.and.iphone",
                    title: state.settingsError == nil ? "No devices yet" : "Devices unavailable",
                    subtitle: "This Mac registers as soon as it connects. iPhone and iPad apps appear after their first request."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(orderedDevices) { device in
                        Button {
                            state.open(device)
                        } label: {
                            DeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                        .help("Show details for \(device.name)")
                        .accessibilityHint("Opens the device's connection details and identity")
                    }
                }
            }
        }
    }

    // MARK: - Deployments

    var deploymentsSection: some View {
        SettingsDeploymentsSection()
    }

    // MARK: - Pairing

    var pairingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Pairing")

            VStack(alignment: .leading, spacing: 10) {
                let link = state.pairingLink

                Text("Scan this code with the iPhone or iPad app's Settings tab, or copy the link.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let link, let code = QRCode.image(for: link) {
                    HStack {
                        Spacer(minLength: 0)
                        Image(nsImage: code)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 140, height: 140)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.black.opacity(0.08))
                            )
                            .accessibilityLabel("Pairing QR code")
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }

                HStack(spacing: 8) {
                    Text(link == nil ? "Unavailable" : "opencodebar://pair?url=…&token=…")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(link == nil ? .tertiary : .secondary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        copyPairingLink()
                    } label: {
                        Label(copiedPairingLink ? "Copied" : "Copy", systemImage: copiedPairingLink ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(link == nil)
                }

                Text("The link and QR code contain the hub token; share them only with your own devices.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    // MARK: - Connection

    var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Connection")

            VStack(alignment: .leading, spacing: 8) {
                serverRow("Status", state.connection.label)
                if let device = state.devices.first(where: \.isThisDevice) {
                    serverRow("This device", device.name)
                }
                serverRow("Discovery", discoveryLabel)
            }
            .card()
        }
    }

}

/// Width of the settings content, used to pick a one, two, or three-column
/// layout on desktop windows.
private struct SettingsWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Exact width available to Settings inside the desktop window's scroll view.
struct SettingsAvailableWidthKey: EnvironmentKey {
    static var defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var settingsAvailableWidth: CGFloat? {
        get { self[SettingsAvailableWidthKey.self] }
        set { self[SettingsAvailableWidthKey.self] = newValue }
    }
}
