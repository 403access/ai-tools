import AppKit
import SwiftUI

/// Hub settings: who is connected, what the server is doing, and the controls
/// needed to manage it. Pairing lives here too so a new phone can be added
/// without opening a terminal.
struct SettingsTab: View {
    @EnvironmentObject var state: AppState

    @State private var copiedPairingLink = false
    @State private var showRestartConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let error = state.settingsError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            } else if let notice = state.settingsNotice {
                NoticeRow(icon: "checkmark.circle.fill", message: notice, tint: Theme.accent)
            }

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

    // MARK: - Server

    private var serverSection: some View {
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

    private var updatesSection: some View {
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

    private var throttleBinding: Binding<Int> {
        Binding(
            get: { state.serverSettings?.eventThrottleMs ?? 0 },
            set: { value in
                Task { await state.updateEventThrottle(value) }
            }
        )
    }

    private var throttleOptions: [Int] {
        var values = [0, 100, 250, 500, 1_000, 2_000]
        if let current = state.serverSettings?.eventThrottleMs, !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values
    }

    private func throttleLabel(_ milliseconds: Int) -> String {
        if milliseconds == 0 { return "Off" }
        if milliseconds % 1_000 == 0 { return "\(milliseconds / 1_000) s" }
        return "\(milliseconds) ms"
    }

    // MARK: - Devices

    private var devicesSection: some View {
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
                VStack(spacing: 8) {
                    ForEach(orderedDevices) { device in
                        DeviceRow(device: device)
                    }
                }
            }
        }
    }

    // MARK: - Pairing

    private var pairingSection: some View {
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

    private var connectionSection: some View {
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

    // MARK: - Pieces

    private var serverHealth: HubHealthResponse.Hub? {
        state.hubHealth?.hub ?? state.hubInfo?.hub
    }

    private var serverOnline: Bool {
        state.hubHealth?.ok == true || state.connection.isConnected
    }

    private var opencodeLabel: String {
        let opencode = state.hubHealth?.opencode
        guard opencode?.connected == true else {
            if let error = opencode?.lastError, !error.isEmpty { return "offline · \(error)" }
            return "offline"
        }
        return opencode?.version.map { "connected · v\($0)" } ?? "connected"
    }

    private var cachedLabel: String? {
        guard let hub = serverHealth else { return nil }
        return "\(Fmt.grouped(hub.sessions ?? 0)) sessions · \(Fmt.grouped(hub.messages ?? 0)) messages"
    }

    private var discoveryLabel: String {
        if ProcessInfo.processInfo.environment["OPENCODEBAR_HUB_URL"] != nil
            || ProcessInfo.processInfo.environment["OPENCODEBAR_HUB_TOKEN"] != nil {
            return "Environment override"
        }
        return "Local hub config"
    }

    private var orderedDevices: [ConnectedDevice] {
        state.devices.sorted { first, second in
            if first.connected != second.connected { return first.connected }
            return first.lastSeen > second.lastSeen
        }
    }

    private var deviceCountLabel: String {
        let connected = state.devices.filter(\.connected).count
        if connected == 0 { return "\(state.devices.count) known" }
        return "\(connected) connected"
    }

    private func serverRow(_ label: String, _ value: String, monospaced: Bool = false, lineLimit: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: monospaced ? .monospaced : .default))
                .lineLimit(lineLimit)
                .multilineTextAlignment(.trailing)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours < 24 { return "\(hours)h \(minutes)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    // MARK: - Actions

    private func copyPairingLink() {
        guard let link = state.pairingLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copiedPairingLink = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedPairingLink = false
        }
    }

    private func revealServerFiles() {
        let fileManager = FileManager.default
        let dataDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencodebar", isDirectory: true)
        let configFile = ServiceDiscovery.configDir().appendingPathComponent("opencodebar-hub.json")

        let target: URL
        if let db = serverHealth?.db, fileManager.fileExists(atPath: db) {
            target = URL(fileURLWithPath: db)
        } else if fileManager.fileExists(atPath: configFile.path) {
            target = configFile
        } else {
            target = dataDir
        }
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}

private struct DeviceRow: View {
    let device: ConnectedDevice

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(device.connected ? Theme.accent : Color.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(device.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    if device.isThisDevice {
                        Chip(text: "this Mac", tint: Theme.accent)
                    }
                    Spacer(minLength: 4)
                    if device.connected {
                        PulsingDot(size: 4)
                    }
                }

                HStack(spacing: 5) {
                    Text(device.platform)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    if !device.appVersion.isEmpty {
                        Text("v\(device.appVersion)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 4)
                    Text(device.connected ? "Connected" : Fmt.relative(from: device.lastSeenDate))
                        .font(.system(size: 9))
                        .foregroundStyle(device.connected ? Theme.accent : .secondary)
                }
            }
        }
        .card(padding: 10)
    }

    private var icon: String {
        switch device.platform.lowercased() {
        case "macos": return "desktopcomputer"
        case "ipados": return "ipad"
        case "ios": return "iphone"
        default: return device.isThisDevice ? "desktopcomputer" : "questionmark.circle"
        }
    }
}
