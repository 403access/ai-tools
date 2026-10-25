import SwiftUI

/// Live serial console pane shared by macOS and iOS. It owns its connection so
/// changing tabs or reconnecting creates a fresh socket.
struct VMConsolePane: View {
    @StateObject private var connection: VMConsoleConnection
    var height: CGFloat = 300

    init(api: HubAPI, machineID: String, height: CGFloat = 300) {
        _connection = StateObject(
            wrappedValue: VMConsoleConnection(api: api, machineID: machineID)
        )
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle()
                    .fill(connection.state.isConnected ? Theme.accent : Theme.warn)
                    .frame(width: 6, height: 6)
                Text(connection.state.label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    connection.disconnect()
                    connection.connect()
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                        .font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }

            TerminalEmulatorView(connection: connection)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
        .onAppear { connection.connect() }
        .onDisappear { connection.disconnect() }
    }
}

/// Explains the host prerequisites without pretending the hub can install
/// packages or enable a Linux builder without the user's password.
struct VMSetupNotice: View {
    let capabilities: VMCapabilities

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                Text("Host setup needed")
                    .font(.system(size: 11, weight: .semibold))
            }

            ForEach(capabilities.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 3) {
                if !capabilities.helperAvailable || !capabilities.helperEntitled {
                    command("make vz-helper")
                }
                if !capabilities.nixAvailable {
                    command("curl -L https://nixos.org/nix/install | sh")
                }
                if capabilities.nixAvailable && !capabilities.linuxBuilder {
                    command("nix run nixpkgs#darwin.linux-builder")
                    Text("Accepts the Nix daemon settings after one sudo prompt. Restart the hub afterwards.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card(padding: 10)
    }

    private func command(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, design: .monospaced))
            .textSelection(.enabled)
            .foregroundStyle(.primary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
    }
}

/// Wrapping chip row used for package lists.
struct FlowChips: View {
    let items: [String]
    var tint: Color = Theme.accent
    var columns = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(chunked, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { item in
                        Chip(text: item, tint: tint)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var chunked: [[String]] {
        stride(from: 0, to: items.count, by: max(1, columns)).map { start in
            Array(items[start..<min(start + max(1, columns), items.count)])
        }
    }
}
