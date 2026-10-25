import SwiftUI
import UIKit

/// Phone detail for one VM: the same overview, serial console, package editor
/// and logs as the Mac, arranged for touch.
struct VirtualMachineMobileDetailView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case console = "Console"
        case packages = "Packages"
        case logs = "Logs"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.33percent"
            case .console: return "terminal"
            case .packages: return "shippingbox"
            case .logs: return "doc.text"
            }
        }
    }

    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let machineID: String
    @ObservedObject var model: VirtualMachinesStore

    @State private var mode: Mode = .overview
    @State private var logType: VMLogType = .build
    @State private var packageDraft = ""
    @State private var showingDelete = false
    @State private var showingRebuild = false
    @State private var copied = false

    private var machine: VirtualMachine? { model.machine(machineID) }
    private var guest: VirtualMachine.GuestMetrics? { machine?.metrics?.guest }
    private var host: VirtualMachine.HostMetrics? { machine?.metrics?.host }
    private var isActing: Bool {
        guard let machine else { return false }
        return model.actionsInFlight.contains(machine.id)
    }

    var body: some View {
        Group {
            if let machine {
                content(machine)
            } else {
                EmptyState(
                    icon: "server.rack",
                    title: "Virtual machine not found",
                    subtitle: "It may have been deleted on the hub."
                )
                .padding(16)
            }
        }
        .mobileScreenBackground()
        .navigationTitle(machine?.name ?? "Virtual Machine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let machine, let command = machine.sshCommand {
                        Button {
                            UIPasteboard.general.string = command
                            copied = true
                        } label: {
                            Label("Copy SSH command", systemImage: "doc.on.doc")
                        }
                    }
                    Button(role: .destructive) {
                        showingRebuild = true
                    } label: {
                        Label("Rebuild image…", systemImage: "hammer")
                    }
                    Button(role: .destructive) {
                        showingDelete = true
                    } label: {
                        Label("Delete VM…", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(machine == nil)
            }
        }
        .confirmationDialog(
            "Rebuild “\(machine?.name ?? "VM")”?",
            isPresented: $showingRebuild,
            titleVisibility: .visible
        ) {
            Button("Replace the disk", role: .destructive) {
                guard let machine else { return }
                Task {
                    await model.control(api: store.api, machine: machine, action: "rebuild", force: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Rebuilding replaces the guest disk and loses everything installed or saved inside NixOS.")
        }
        .confirmationDialog(
            "Delete “\(machine?.name ?? "VM")”?",
            isPresented: $showingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete VM and disk", role: .destructive) {
                guard let machine else { return }
                Task {
                    await model.remove(api: store.api, machine: machine, force: true)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The disk image, SSH key, logs, and all data inside the guest are removed.")
        }
    }

    @ViewBuilder
    private func content(_ machine: VirtualMachine) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(machine)
                actionBar(machine)

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .labelStyle(.titleAndIcon)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: mode) { _, _ in
                    if mode == .logs { Task { await loadLog(machine) } }
                }

                switch mode {
                case .overview: overview(machine)
                case .console: consoleTab(machine)
                case .packages: packagesTab(machine)
                case .logs: logsTab(machine)
                }
            }
            .padding(16)
        }
        .refreshable { await model.refreshSelected(api: store.api) }
        .task(id: machine.status) {
            if machine.status == .building || machine.status == .error {
                await model.loadLog(api: store.api, machine: machine, type: .build, tail: 120)
            }
        }
    }

    // MARK: - Header and actions

    private func header(_ machine: VirtualMachine) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(statusColor(machine).opacity(0.14))
                Image(systemName: "server.rack")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(statusColor(machine))
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(machine.name)
                        .font(.headline)
                        .lineLimit(1)
                    Chip(text: machine.status.label, tint: statusColor(machine))
                }
                HStack(spacing: 6) {
                    Text("NixOS · \(machine.channel)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let ip = machine.network.ip {
                        Text(ip)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(machine.network.reachable ? Theme.accent : .secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actionBar(_ machine: VirtualMachine) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if isActing {
                    ProgressView().controlSize(.small)
                }
                switch machine.status {
                case .stopped, .error, .unknown:
                    actionButton("Start", icon: "play.fill", tint: Theme.accent) {
                        await model.control(api: store.api, machine: machine, action: "start")
                    }
                case .running:
                    actionButton("Stop", icon: "stop.fill", tint: Theme.danger) {
                        await model.control(api: store.api, machine: machine, action: "stop")
                    }
                    actionButton("Pause", icon: "pause.fill", tint: .secondary) {
                        await model.control(api: store.api, machine: machine, action: "pause")
                    }
                    actionButton("Restart", icon: "arrow.clockwise", tint: .secondary) {
                        await model.control(api: store.api, machine: machine, action: "restart")
                    }
                case .paused:
                    actionButton("Resume", icon: "play.fill", tint: Theme.accent) {
                        await model.control(api: store.api, machine: machine, action: "resume")
                    }
                    actionButton("Stop", icon: "stop.fill", tint: Theme.danger) {
                        await model.control(api: store.api, machine: machine, action: "stop")
                    }
                case .starting:
                    actionButton("Stop", icon: "stop.fill", tint: Theme.danger) {
                        await model.control(api: store.api, machine: machine, action: "stop", force: true)
                    }
                case .building:
                    Text("Building the NixOS image…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .stopping:
                    Text("Waiting for the guest to stop…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if machine.hasPendingPackages, !isActing {
                    actionButton("Apply", icon: "arrow.triangle.2.circlepath", tint: Theme.warn) {
                        await model.control(api: store.api, machine: machine, action: "apply")
                    }
                }
            }

            if let progress = machine.progress {
                HStack(alignment: .top, spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(progress.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(padding: 10)
            }

            if let error = machine.lastError, machine.status != .running {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.danger)
            }

            if let error = model.error {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            }
        }
    }

    private func actionButton(
        _ title: String,
        icon: String,
        tint: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .foregroundStyle(isActing ? Color.secondary : tint)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .disabled(isActing)
    }

    // MARK: - Overview

    private func overview(_ machine: VirtualMachine) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                StatTile(icon: "cpu", tint: Theme.input, label: "CPU", value: cpuValue, caption: cpuCaption)
                StatTile(icon: "memorychip", tint: Theme.reasoning, label: "Memory", value: memoryValue, caption: memoryCaption)
                StatTile(icon: "internaldrive", tint: Theme.output, label: "Disk", value: diskValue, caption: diskCaption)
                StatTile(icon: "clock", tint: Theme.warn, label: "Uptime", value: uptimeValue, caption: uptimeCaption)
            }

            if let guest, let fraction = guest.memoryFraction {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Guest memory")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.bytes(guest.memoryUsedBytes)) / \(Fmt.bytes(guest.memoryTotalBytes))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(fraction, 0), 1))
                        .tint(Theme.reasoning)
                }
                .card()
            }

            if let guest, let fraction = guest.diskFraction {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Guest disk")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Fmt.bytes(guest.diskUsedBytes)) / \(Fmt.bytes(guest.diskTotalBytes))")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(fraction, 0), 1))
                        .tint(Theme.output)
                }
                .card()
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("Network & SSH") {
                    if let ip = machine.network.ip {
                        Chip(
                            text: ip,
                            tint: machine.network.reachable ? Theme.accent : .secondary
                        )
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    infoRow("Address", machine.network.ip ?? "Waiting for DHCP")
                    infoRow("MAC", machine.network.mac, mono: true)
                    infoRow("User", machine.ssh.user, mono: true)
                    if let command = machine.sshCommand {
                        Divider().opacity(0.35).padding(.vertical, 6)
                        HStack(alignment: .top, spacing: 6) {
                            Text(command)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Spacer(minLength: 4)
                            Button {
                                UIPasteboard.general.string = command
                                copied = true
                            } label: {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .card()
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader("NixOS")
                VStack(alignment: .leading, spacing: 0) {
                    infoRow("Hostname", guest?.hostname ?? "—")
                    infoRow("Kernel", guest?.kernel ?? "—", mono: true)
                    infoRow("Load", loadValue(machine))
                    infoRow("State version", machine.stateVersion)
                    infoRow("Generation", guest?.generation.map(generationLabel) ?? "—", mono: true)
                    infoRow("Image size", Fmt.bytes(host?.diskBytes))
                    infoRow("Helper RSS", Fmt.bytes(host?.rssBytes))
                }
                .card()
            }

            if !machine.packages.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader("Packages") {
                        Button("Manage") { mode = .packages }
                            .font(.caption2.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.accent)
                    }
                    FlowChips(items: machine.packages, tint: Theme.accent, columns: 2)
                        .card()
                }
            }
        }
    }

    // MARK: - Console

    @ViewBuilder
    private func consoleTab(_ machine: VirtualMachine) -> some View {
        if let api = store.api,
           machine.status == .running || machine.status == .paused || machine.status == .starting {
            VMConsolePane(api: api, machineID: machine.id, height: 360)
                .id("\(machine.id)-\(machine.startedAt ?? 0)")
        } else {
            EmptyState(
                icon: "terminal",
                title: "Serial console",
                subtitle: "Start the virtual machine to attach to its serial console."
            )
        }
    }

    // MARK: - Packages

    private func packagesTab(_ machine: VirtualMachine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Packages are declarative. While the VM is running the hub writes configuration.nix and runs nixos-rebuild switch over SSH; while it is stopped the change waits for the next boot.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("BASE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                FlowChips(items: ["curl", "git", "htop", "vim"], tint: .secondary, columns: 2)
            }
            .card()

            VStack(alignment: .leading, spacing: 9) {
                if machine.packages.isEmpty {
                    Text("No extra packages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(machine.packages, id: \.self) { name in
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                        Text(name)
                            .font(.system(size: 13, design: .monospaced))
                        Spacer()
                        Button {
                            updatePackages(machine, packages: machine.packages.filter { $0 != name })
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(isActing || machine.status == .building)
                    }
                    Divider().opacity(0.3)
                }

                HStack(spacing: 7) {
                    TextField("nixpkgs attribute", text: $packageDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { addPackage(machine) }
                        .disabled(isActing || machine.status == .building)
                    Button("Add") { addPackage(machine) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .disabled(
                            packageDraft.trimmingCharacters(in: .whitespaces).isEmpty ||
                                isActing || machine.status == .building
                        )
                }
            }
            .card()

            if machine.hasPendingPackages {
                NoticeRow(
                    icon: "arrow.triangle.2.circlepath",
                    message: machine.status == .running
                        ? "Package changes are queued for the next apply."
                        : "Package changes will be applied on the next boot.",
                    tint: Theme.warn
                )
            }

            if machine.status == .running, machine.network.reachable, !machine.hasPendingPackages {
                Button {
                    Task { await model.control(api: store.api, machine: machine, action: "apply") }
                } label: {
                    Label("Re-apply configuration", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Theme.accent)
                .disabled(isActing)
            }
        }
    }

    // MARK: - Logs

    private func logsTab(_ machine: VirtualMachine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $logType) {
                ForEach(VMLogType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: logType) { _, _ in
                Task { await loadLog(machine) }
            }

            HStack {
                Text(model.log(for: machine.id, type: logType)?.path ?? "—")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    Task { await loadLog(machine) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Button {
                    UIPasteboard.general.string = model.log(for: machine.id, type: logType)?
                        .lines.joined(separator: "\n") ?? ""
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(logText(machine))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 320)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.22))
            )

            if model.log(for: machine.id, type: logType)?.truncated == true {
                Text("Showing the end of the log.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: logType) {
            await loadLog(machine)
        }
    }

    // MARK: - Helpers

    private func statusColor(_ machine: VirtualMachine) -> Color {
        switch machine.status {
        case .running: return Theme.running
        case .starting, .building, .stopping: return Theme.warn
        case .paused: return Theme.reasoning
        case .error: return Theme.danger
        case .stopped, .unknown: return .secondary
        }
    }

    private var cpuValue: String {
        if let value = guest?.cpuPercent { return "\(Int(value.rounded()))%" }
        if let value = host?.cpuPercent { return "\(Int(value.rounded()))%" }
        return "—"
    }

    private var cpuCaption: String {
        guest?.cpuPercent != nil ? "guest" : (host?.cpuPercent != nil ? "helper" : "not sampled")
    }

    private var memoryValue: String {
        if let guest, let used = guest.memoryUsedBytes { return Fmt.bytes(used) }
        return machine.map { "\($0.memoryMB / 1_024) GB" } ?? "—"
    }

    private var memoryCaption: String {
        if let guest, let total = guest.memoryTotalBytes { return "of \(Fmt.bytes(total))" }
        return "configured"
    }

    private var diskValue: String {
        if let guest, let used = guest.diskUsedBytes { return Fmt.bytes(used) }
        if let host, let used = host.diskUsedBytes { return Fmt.bytes(used) }
        return "—"
    }

    private var diskCaption: String {
        if let guest, let total = guest.diskTotalBytes { return "of \(Fmt.bytes(total))" }
        if let host, let total = host.diskBytes { return "of \(Fmt.bytes(total)) image" }
        return "not built"
    }

    private var uptimeValue: String {
        if let value = guest?.uptimeSec { return Fmt.uptime(value) }
        if let value = host?.uptimeSec { return Fmt.uptime(value) }
        return "—"
    }

    private var uptimeCaption: String {
        guest?.uptimeSec != nil ? "guest" : (host?.uptimeSec != nil ? "helper" : "not running")
    }

    private func loadValue(_ machine: VirtualMachine) -> String {
        guard let guest, let one = guest.load1 else { return "—" }
        let five = guest.load5 ?? one
        let fifteen = guest.load15 ?? five
        return String(format: "%.2f  %.2f  %.2f", one, five, fifteen)
    }

    private func generationLabel(_ generation: String) -> String {
        let name = (generation as NSString).lastPathComponent
        return name.isEmpty ? generation : name
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.system(size: mono ? 10 : 11, design: mono ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func logText(_ machine: VirtualMachine) -> String {
        guard let log = model.log(for: machine.id, type: logType) else {
            return "Loading…"
        }
        return log.lines.isEmpty ? "Nothing here yet." : log.lines.joined(separator: "\n")
    }

    private func loadLog(_ machine: VirtualMachine) async {
        await model.loadLog(api: store.api, machine: machine, type: logType)
    }

    private func addPackage(_ machine: VirtualMachine) {
        let name = packageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !machine.packages.contains(name) else { return }
        packageDraft = ""
        updatePackages(machine, packages: machine.packages + [name])
    }

    private func updatePackages(_ machine: VirtualMachine, packages: [String]) {
        Task {
            await model.update(api: store.api, machine: machine, packages: packages)
        }
    }
}
