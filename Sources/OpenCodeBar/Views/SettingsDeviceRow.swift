import SwiftUI

/// One row in Settings → Devices. The row is presentational; the Settings tab
/// wraps it in a button that opens the device's detail page.
struct DeviceRow: View {
    let device: ConnectedDevice

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
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

            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 10)
        .contentShape(Rectangle())
    }

    private var icon: String {
        if device.platformIconName == "questionmark.circle", device.isThisDevice {
            return "desktopcomputer"
        }
        return device.platformIconName
    }
}
