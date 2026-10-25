import SwiftUI

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

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

/// Interactive host setup card shown in the VMs tab. The hub runs fixed,
/// allow-listed commands; the Nix installer asks for the Mac administrator
/// password in a macOS dialog, and the phone watches the streamed log.
struct VMSetupRunnerCard: View {
    let capabilities: VMCapabilities
    @ObservedObject var model: VirtualMachinesStore
    let api: HubAPI?

    private var job: VMSetupJob? { model.setup }
    private var running: Bool { job?.status == .running }
    private var runningStep: VMSetupStep? { running ? job?.stepValue : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.warn)
                Text("Host setup needed")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                if let job {
                    Chip(text: job.status.label, tint: statusColor(job.status))
                }
            }

            ForEach(capabilities.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !capabilities.nixAvailable {
                setupAction(.nix)
            }

            if !capabilities.helperAvailable || !capabilities.helperEntitled {
                setupAction(.helper)
            }

            if capabilities.nixAvailable && !capabilities.linuxBuilder {
                builderAction
            }

            if let job {
                jobProgress(job)
            }
        }
        .card(padding: 10)
        .task(id: job?.status) {
            guard job?.status == .running else { return }
            while !Task.isCancelled {
                await model.refreshSetup(api: api)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func setupAction(_ step: VMSetupStep) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(step.title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                if runningStep == step {
                    ProgressView().controlSize(.small).scaleEffect(0.75)
                } else {
                    Button("Run") {
                        Task { await model.startSetup(api: api, step: step) }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(running || model.actionsInFlight.contains("setup:\(step.rawValue)"))
                }
            }

            Text(step.command)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )

            if step == .nix {
                Text("macOS asks for your administrator password on the Mac. The installer runs on the Mac, not on the phone.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var builderAction: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Linux builder")
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 4)
                Button("Copy") {
                    copy("nix run nixpkgs#darwin.linux-builder")
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            Text("Run this once in Terminal on the Mac. It starts a NixOS builder VM and needs to stay running for image builds.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("nix run nixpkgs#darwin.linux-builder")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
    }

    private func jobProgress(_ job: VMSetupJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().opacity(0.4)

            HStack(spacing: 7) {
                if job.status == .running {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                Text(jobMessage(job))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(job.status == .failed ? Theme.danger : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if job.status == .running {
                    Button("Cancel") {
                        Task { await model.cancelSetup(api: api) }
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.danger)
                }
            }

            if !job.log.lines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(job.log.lines.suffix(120).joined(separator: "\n"))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .id("vm-setup-log-end")
                    }
                    .frame(height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.black.opacity(0.20))
                    )
                    .onChange(of: job.log.lines.count) { _, _ in
                        proxy.scrollTo("vm-setup-log-end", anchor: .bottom)
                    }
                }
            } else if job.status == .running {
                Text(job.requiresAdmin && job.status == .running
                    ? "Waiting for the administrator prompt on the Mac…"
                    : "Waiting for output…")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func jobMessage(_ job: VMSetupJob) -> String {
        switch job.status {
        case .running:
            return job.requiresAdmin
                ? "Enter the administrator password in the dialog on the Mac."
                : "Running on the Mac…"
        case .succeeded:
            return "Finished. Refreshing host capabilities…"
        case .failed:
            return job.error ?? "Setup failed."
        case .cancelled:
            return "Setup cancelled."
        case .unknown:
            return "Setup state unknown."
        }
    }

    private func statusColor(_ status: VMSetupJobStatus) -> Color {
        switch status {
        case .running: return Theme.warn
        case .succeeded: return Theme.accent
        case .failed: return Theme.danger
        case .cancelled, .unknown: return .secondary
        }
    }

    private func copy(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
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
