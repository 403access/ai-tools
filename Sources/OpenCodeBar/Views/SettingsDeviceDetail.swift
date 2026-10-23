import AppKit
import SwiftUI

/// Full-panel detail for one device that has connected to the hub. Opened by
/// clicking its row in Settings → Devices. The live state is read back from
/// `AppState.devices` so the page keeps updating while it is open.
struct DeviceDetailView: View {
    @EnvironmentObject private var state: AppState
    let device: ConnectedDevice

    @State private var copiedID = false

    private var liveDevice: ConnectedDevice {
        state.devices.first(where: { $0.id == device.id }) ?? device
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            navigationBar
            summary

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    connectionSection
                    identitySection

                    if liveDevice.isThisDevice {
                        NoticeRow(
                            icon: "checkmark.seal.fill",
                            message: "This is the Mac you are using. Its row stays connected while OpenCodeBar is running.",
                            tint: Theme.accent
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .task { await state.refreshSettings() }
        .onExitCommand { state.closeDevice() }
    }

    // MARK: - Header

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                state.closeDevice()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Settings")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to settings")

            Spacer(minLength: 8)

            Button {
                Task { await state.refreshSettings(force: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh device details")
            .disabled(state.isRefreshingSettings)

            if liveDevice.connected {
                HStack(spacing: 5) {
                    PulsingDot(size: 6)
                    Text("Connected")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.running)
                }
            } else {
                Chip(text: "Offline")
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(liveDevice.connected ? Theme.accent : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(liveDevice.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(2)
                        if liveDevice.isThisDevice {
                            Chip(text: "this Mac", tint: Theme.accent)
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Label(
                    liveDevice.connected
                        ? "Live now"
                        : "Last seen \(Fmt.relative(from: liveDevice.lastSeenDate))",
                    systemImage: liveDevice.connected ? "bolt.horizontal.circle" : "clock"
                )
                Label("Since \(Self.dateFormatter.string(from: liveDevice.firstSeenDate))", systemImage: "calendar")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private var subtitle: String {
        var parts = [liveDevice.platform]
        if !liveDevice.appVersion.isEmpty {
            parts.append("v\(liveDevice.appVersion)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Sections

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Connection")

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Status")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(liveDevice.connected ? Theme.accent : Color.secondary.opacity(0.6))
                            .frame(width: 5, height: 5)
                        Text(liveDevice.connected ? "Connected" : "Not connected")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(liveDevice.connected ? Theme.accent : .secondary)
                    }
                }

                Divider().opacity(0.4)

                detailRow("Last seen", "\(Fmt.relative(from: liveDevice.lastSeenDate)) · \(Self.dateTimeFormatter.string(from: liveDevice.lastSeenDate))")
                detailRow("First seen", Self.dateTimeFormatter.string(from: liveDevice.firstSeenDate))
                detailRow("Platform", liveDevice.platform)
                detailRow(
                    "App version",
                    liveDevice.appVersion.isEmpty ? "Unknown" : "v\(liveDevice.appVersion)",
                    monospaced: true
                )
            }
            .card()
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Identity")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Device ID")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        copyDeviceID()
                    } label: {
                        Label(
                            copiedID ? "Copied" : "Copy",
                            systemImage: copiedID ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                }

                Text(liveDevice.id)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Text("The app generates this identifier once and sends it with every request, so the hub can keep the device's history together.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    // MARK: - Pieces

    private var icon: String {
        if liveDevice.platformIconName == "questionmark.circle", liveDevice.isThisDevice {
            return "desktopcomputer"
        }
        return liveDevice.platformIconName
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: monospaced ? .monospaced : .default))
                .multilineTextAlignment(.trailing)
                .truncationMode(.middle)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    // MARK: - Actions

    private func copyDeviceID() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(liveDevice.id, forType: .string)
        copiedID = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedID = false
        }
    }
}
