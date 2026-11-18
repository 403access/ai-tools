import AppKit
import SwiftUI

/// Settings segment that lists the MCP servers OpenCode will launch for an
/// agent. The configuration stays in OpenCode's own files; this card only reads
/// them and offers the OpenCodeBar registration command.
struct SettingsMCPSection: View {
    @State private var snapshot = MCPConfigurationSnapshot.empty
    @State private var loaded = false
    @State private var copiedCommand = false

    private let docsURL = URL(string: "https://403access.github.io/ai-tools/docs/hub/mcp")!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("MCP servers") {
                HStack(spacing: 6) {
                    if !loaded {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    }
                    if snapshot.isOpenCodeBarRegistered {
                        Chip(text: "OpenCodeBar", systemImage: "checkmark.circle.fill", tint: Theme.accent)
                    }
                    Text("\(snapshot.servers.count) configured")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .help("Read the OpenCode config files again")
                    .accessibilityLabel("Refresh MCP servers")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("MCP servers give an agent named tools for OpenCode and the Mac. OpenCodeBar ships a local server with projects, sessions, tasks, terminals, host status, and virtual machines, all through the hub.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if snapshot.servers.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(snapshot.servers.enumerated()), id: \.element.id) { index, server in
                            if index > 0 { Divider().opacity(0.5) }
                            serverRow(server)
                        }
                    }
                }

                if !snapshot.errors.isEmpty {
                    Text(snapshot.errors.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().opacity(0.5)

                if snapshot.isOpenCodeBarRegistered {
                    Text("The OpenCodeBar server is registered. OpenCode sessions can start work, follow a conversation, read changes and stats, and resolve the task board.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The OpenCodeBar server is not in these config files yet. Register it globally so every OpenCode session can use it:")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(setupCommand)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        copySetupCommand()
                    } label: {
                        Label(
                            copiedCommand ? "Copied" : "Copy command",
                            systemImage: copiedCommand ? "checkmark" : "doc.on.doc",
                        )
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        NSWorkspace.shared.open(docsURL)
                    } label: {
                        Label("MCP guide", systemImage: "book")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        revealConfig()
                    } label: {
                        Label("Show config", systemImage: "folder")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(snapshot.configFiles.isEmpty)
                }

                Text("Read from ~/.config/opencode/opencode.json and the repository's opencode.json. Restart OpenCode after editing either file.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
        .task { reload() }
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 18))
                .foregroundStyle(.tertiary)
            Text("No MCP servers found")
                .font(.system(size: 11, weight: .medium))
            Text("Add one to OpenCode's config, or register the OpenCodeBar server below.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private func serverRow(_ server: MCPServerInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: server.type == "remote" ? "network" : "puzzlepiece.extension")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(server.isOpenCodeBar ? Theme.accent : .secondary)

                Text(server.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                if server.isOpenCodeBar {
                    Chip(text: "Hub tools", tint: Theme.accent)
                }

                Spacer(minLength: 4)

                Chip(text: server.scope.rawValue, tint: .secondary)
                Chip(text: server.type.capitalized, tint: server.type == "remote" ? Theme.reasoning : .secondary)
            }

            Text(server.detail)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Text((server.sourcePath as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(server.sourcePath)
        }
    }

    // MARK: - Actions

    private var setupCommand: String {
        if let server = HubLauncher.serverDirectory() {
            let script = server.appendingPathComponent("src/mcp/server.ts").path
            return "opencode mcp add opencodebar --global -- bun \(shellQuoted(script))"
        }
        return "opencode mcp add opencodebar --global -- bun \"$PWD/server/src/mcp/server.ts\""
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func reload() {
        snapshot = MCPConfiguration.load()
        loaded = true
    }

    private func copySetupCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(setupCommand, forType: .string)
        copiedCommand = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedCommand = false
        }
    }

    private func revealConfig() {
        guard let file = snapshot.configFiles.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}