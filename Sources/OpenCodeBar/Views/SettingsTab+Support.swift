import AppKit
import SwiftUI

extension SettingsTab {
    // MARK: - Pieces

    var serverHealth: HubHealthResponse.Hub? {
        state.hubHealth?.hub ?? state.hubInfo?.hub
    }

    var serverOnline: Bool {
        state.hubHealth?.ok == true || state.connection.isConnected
    }

    var opencodeLabel: String {
        let opencode = state.hubHealth?.opencode
        guard opencode?.connected == true else {
            if let error = opencode?.lastError, !error.isEmpty { return "offline · \(error)" }
            return "offline"
        }
        return opencode?.version.map { "connected · v\($0)" } ?? "connected"
    }

    var cachedLabel: String? {
        guard let hub = serverHealth else { return nil }
        return "\(Fmt.grouped(hub.sessions ?? 0)) sessions · \(Fmt.grouped(hub.messages ?? 0)) messages"
    }

    var discoveryLabel: String {
        if ProcessInfo.processInfo.environment["OPENCODEBAR_HUB_URL"] != nil
            || ProcessInfo.processInfo.environment["OPENCODEBAR_HUB_TOKEN"] != nil {
            return "Environment override"
        }
        return "Local hub config"
    }

    var orderedDevices: [ConnectedDevice] {
        state.devices.sorted { first, second in
            if first.connected != second.connected { return first.connected }
            return first.lastSeen > second.lastSeen
        }
    }

    var deviceCountLabel: String {
        let connected = state.devices.filter(\.connected).count
        if connected == 0 { return "\(state.devices.count) known" }
        return "\(connected) connected"
    }

    func serverRow(_ label: String, _ value: String, monospaced: Bool = false, lineLimit: Int = 1) -> some View {
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

    func duration(seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours < 24 { return "\(hours)h \(minutes)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    // MARK: - Actions

    func copyPairingLink() {
        guard let link = state.pairingLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        copiedPairingLink = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedPairingLink = false
        }
    }

    func revealServerFiles() {
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
