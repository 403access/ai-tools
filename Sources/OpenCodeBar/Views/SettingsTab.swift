import AppKit
import SwiftUI

/// Hub settings: who is connected, what the server is doing, and the controls
/// needed to manage it. Pairing lives here too so a new phone can be added
/// without opening a terminal.
struct SettingsTab: View {
    @EnvironmentObject var state: AppState

    @State var copiedPairingLink = false
    @State private var showRestartConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = state.settingsError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            } else if let notice = state.settingsNotice {
                NoticeRow(icon: "checkmark.circle.fill", message: notice, tint: Theme.accent)
            }

            appSection
            powerSection
            serverSection
            updatesSection
            devicesSection
            pairingSection
            connectionSection
        }
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

                HStack(spacing: 8) {
                    Button {
                        Task { await state.syncNow() }
                    } label: {
                        Label(state.isSyncing ? "Syncing…" : "Sync now", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isSyncing || !serverOnline)

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
