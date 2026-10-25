import AppKit
import SwiftUI

/// One VM's status, metrics, serial console, packages and logs.
struct VirtualMachineDetailView: View {
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

    @EnvironmentObject private var state: AppState
    let machine: VirtualMachine
    @ObservedObject var model: VirtualMachinesStore
    let onBack: () -> Void
    let onDelete: () -> Void
    let onRebuild: () -> Void

    @State private var mode: Mode = .overview
    @State private var logType: VMLogType = .build
    @State private var packageDraft = ""
    @State private var copied = false
    @State private var showingBuilder = false

    private var guest: VirtualMachine.GuestMetrics? { machine.metrics?.guest }
    private var host: VirtualMachine.HostMetrics? { machine.metrics?.host }
    private var isActing: Bool { model.actionsInFlight.contains(machine.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            navigationBar
            header
            actionBar

            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .labelStyle(.titleAndIcon)
                        .tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            switch mode {
            case .overview: overview
            case .console: consoleTab
            case .packages: packagesTab
            case .logs: logsTab
            }
        }
        .padding(.bottom, 6)
        .onExitCommand(perform: onBack)
        .sheet(isPresented: $showingBuilder) {
            NixOSConfigSheet(machine: machine, model: model)
        }
        .task(id: machine.id) {
            await loadBuildLogIfNeeded()
        }
        .onChange(of: machine.status) { _, _ in
            Task { await loadBuildLogIfNeeded() }
        }
    }

    // MARK: - Header

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("VMs")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to virtual machines")

            Spacer()

            Button {
                showingBuilder = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.reasoning)
            }
            .buttonStyle(.plain)
            .help("Open the NixOS configuration builder")

            Button {
                copy(machine.sshCommand ?? machine.paths.directory)
            } label: {
                Label(copied ? "Copied" : "SSH", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(machine.sshCommand == nil ? .secondary : Theme.accent)
            .disabled(machine.sshCommand == nil)
            .help("Copy the SSH command")

            Menu {
                Button("Reveal VM folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: machine.paths.directory)
                }
                Button("Copy configuration path") {
                    copy(machine.paths.configuration)
                }
                Divider()
                Button("Rebuild image…", role: .destructive, action: onRebuild)
                Button("Delete VM…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("More actions")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(statusColor.opacity(0.14))
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(machine.status.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(statusColor)
                    if let ip = machine.network.ip {
                        Text(ip)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            if let started = machine.startedDate {
                Text("Up \(Fmt.relative(from: started))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                if isActing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }

                switch machine.status {
                case .stopped, .error, .unknown:
                    actionButton("Start", icon: "play.fill", tint: Theme.accent) {
                        await model.control(api: state.api, machine: machine, action: "start")
                    }
                case .running:
                    actionButton("Stop", icon: "stop.fill", tint: Theme.danger) {
                        await model.control(api: state.api, machine: machine, action: "stop")
                    }
                    actionButton("Pause", icon: "pause.fill", tint: .secondary) {
                        await model.control(api: state.api, machine: machine, action: "pause")
                    }
                    actionButton("Restart", icon: "arrow.clockwise", tint: .secondary) {
                        await model.control(api: state.api, machine: machine, action: "restart")
                    }
                case .paused:
                    actionButton("Resume", icon: "play.fill", tint: Theme.accent) {
                        await model.control(api: state.api, machine: machine, action: "resume")
                    }
                    actionButton("Stop", icon: "stop.fill", tint: Theme.danger) {
                        await model.control(api: state.api, machine: machine, action: "stop")
                    }
                case .starting:
                    actionButton("Stop", icon: "stop.fill", tint: Theme.danger) {
                        await model.control(api: state.api, machine: machine, action: "stop", force: true)
                    }
                case .stopping:
                    Text("Waiting for the guest to stop…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                case .building:
                    Text("Building the NixOS image. The build log is in the Logs tab.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                if machine.hasPendingChanges, machine.status == .running, !isActing {
                    actionButton("Apply", icon: "arrow.triangle.2.circlepath", tint: Theme.warn) {
                        await model.control(api: state.api, machine: machine, action: "apply")
                    }
                }
            }

            if let progress = machine.progress {
                HStack(alignment: .top, spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(progress.message)
                            .font(.system(size: 10, weight: .medium))
                        Text("\(progress.phase) · \(Fmt.relative(from: progress.startedDate))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 8)
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
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .foregroundStyle(isActing ? Color.secondary : tint)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .disabled(isActing)
    }

    // MARK: - Overview

    private var overview: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusSection
            metricsGrid
            resourceSection
            networkSection
            builderSection
            configurationSection
             if !machine.packages.isEmpty { packagesPreview }
            logsPreview
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Status") {
                Chip(text: machine.status.label, systemImage: "circle.fill", tint: statusColor)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    metric("NixOS", machine.channel)
                    metric("Arch", machine.arch)
                    metric("State version", machine.stateVersion)
                }

                if machine.status == .running {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(machine.network.reachable ? Theme.accent : Theme.warn)
                            .frame(width: 6, height: 6)
                        Text(
                            machine.network.reachable
                                ? "SSH is reachable. Package changes can be applied."
                                : "NixOS is running; waiting for the guest address and SSH."
                        )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                }

                if let lastBoot = machine.lastBootDate {
                    Divider().opacity(0.4)
                    HStack(spacing: 14) {
                        metric("Last boot", Fmt.relative(from: lastBoot))
                        if let uptime = guest?.uptimeSec {
                            metric("Guest uptime", Fmt.uptime(uptime))
                        }
                        if let hostUptime = host?.uptimeSec {
                            metric("Helper uptime", Fmt.uptime(hostUptime))
                        }
                    }
                }
            }
            .card()
        }
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            StatTile(
                icon: "cpu",
                tint: Theme.input,
                label: "CPU",
                value: cpuValue,
                caption: cpuCaption
            )
            StatTile(
                icon: "memorychip",
                tint: Theme.reasoning,
                label: "Memory",
                value: memoryValue,
                caption: memoryCaption
            )
            StatTile(
                icon: "internaldrive",
                tint: Theme.output,
                label: "Disk",
                value: diskValue,
                caption: diskCaption
            )
            StatTile(
                icon: "clock",
                tint: Theme.warn,
                label: "Uptime",
                value: uptimeValue,
                caption: uptimeCaption
            )
        }
    }

    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Resources")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    metric("vCPU", "\(machine.cpuCount)")
                    metric("Memory", "\(machine.memoryMB / 1_024) GB")
                    metric("Disk", "\(machine.diskGB) GB")
                }

                if let guest, let fraction = guest.memoryFraction {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Guest memory")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Fmt.bytes(guest.memoryUsedBytes)) / \(Fmt.bytes(guest.memoryTotalBytes))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(max(fraction, 0), 1))
                            .tint(Theme.reasoning)
                    }
                }

                if let guest, let fraction = guest.diskFraction {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Guest disk")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Fmt.bytes(guest.diskUsedBytes)) / \(Fmt.bytes(guest.diskTotalBytes))")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: min(max(fraction, 0), 1))
                            .tint(Theme.output)
                    }
                }

                if let host {
                    Divider().opacity(0.4)
                    HStack(spacing: 14) {
                        metric("Image size", Fmt.bytes(host.diskBytes))
                        metric("Allocated", Fmt.bytes(host.diskUsedBytes))
                        metric("Helper RSS", Fmt.bytes(host.rssBytes))
                    }
                }
            }
            .card()
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Network & SSH") {
                if let ip = machine.network.ip {
                    Chip(text: ip, systemImage: "network", tint: machine.network.reachable ? Theme.accent : .secondary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                infoRow("Address", machine.network.ip ?? "Waiting for DHCP")
                infoRow("MAC", machine.network.mac, mono: true)
                infoRow("User", machine.ssh.user, mono: true)
                infoRow("SSH key", "\(machine.ssh.user)/id_ed25519", mono: true)
                if let command = machine.sshCommand {
                    Divider().opacity(0.35).padding(.vertical, 6)
                    HStack(alignment: .top, spacing: 6) {
                        Text(command)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Button {
                            copy(command)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                        .help("Copy the SSH command")
                    }
                }
            }
            .card()
        }
    }

    private var builderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Configuration") {
                Button("Open builder") { showingBuilder = true }
                    .font(.system(size: 9, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.reasoning)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    metric("Preset", presetLabel)
                    metric("Options", "\(machine.builder.enabled.count)")
                    metric("Users", "\(machine.builder.users.count + 1)")
                    metric("Custom packages", "\(machine.builder.extraPackages.count)")
                }

                if !enabledOptionNames.isEmpty {
                    FlowChips(items: Array(enabledOptionNames.prefix(12)), tint: Theme.reasoning)
                } else {
                    Text("Minimal configuration. Open the builder to add apps, services, and users.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if machine.hasPendingConfig {
                    Text("Builder changes are queued for the next apply.")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warn)
                }
            }
            .card()
        }
    }

    private var presetLabel: String {
        guard let presetID = machine.builder.preset else { return "Custom" }
        return model.catalog?.preset(presetID)?.name ?? presetID
    }

    private var enabledOptionNames: [String] {
        machine.builder.enabled.compactMap { id in
            model.catalog?.option(id)?.name ?? id
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("NixOS") {
                if let generation = guest?.generation {
                    Text(generationLabel(generation))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                infoRow("Hostname", guest?.hostname ?? "—")
                infoRow("Kernel", guest?.kernel ?? "—", mono: true)
                infoRow("Load", loadValue)
                infoRow("Swap used", Fmt.bytes(guest?.swapUsedBytes))
                infoRow("Configuration", machine.paths.configuration, mono: true)
                infoRow("Flake", machine.paths.flake, mono: true)
                Divider().opacity(0.35).padding(.vertical, 6)
                HStack(spacing: 8) {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: machine.paths.directory)
                    } label: {
                        Label("Reveal VM folder", systemImage: "folder")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)

                    Button {
                        copy(machine.paths.configuration)
                    } label: {
                        Label("Copy config path", systemImage: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    private var packagesPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Packages") {
                Button("Manage") { mode = .packages }
                    .font(.system(size: 9, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 8) {
                if machine.packages.isEmpty {
                    Text("No extra packages. Base tools: curl, git, htop, vim.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    FlowChips(items: machine.packages, tint: Theme.accent)
                }
                if machine.hasPendingChanges {
                    Text(
                        machine.hasPendingPackages
                            ? "Pending: \(machine.pendingPackages.joined(separator: ", "))"
                            : "Configuration changes are queued."
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warn)
                    .lineLimit(2)
                }
            }
            .card()
        }
    }

    private var logsPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Logs") {
                Button("Open logs") { mode = .logs }
                    .font(.system(size: 9, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("The build log, serial boot console, and the last package apply are kept on the hub. The Console tab attaches live to the guest.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    metric("Build", Fmt.relative(from: machine.updatedDate))
                    metric("Serial", machine.paths.serialLog)
                    metric("Apply", machine.paths.applyLog)
                }
            }
            .card()
        }
    }

    // MARK: - Console

    @ViewBuilder
    private var consoleTab: some View {
        if let api = state.api, machine.status == .running || machine.status == .paused || machine.status == .starting {
            VMConsolePane(api: api, machineID: machine.id)
                .id("\(machine.id)-\(machine.startedAt ?? 0)")
        } else {
            EmptyState(
                icon: "terminal",
                title: "Serial console",
                subtitle: machine.status == .building
                    ? "The console becomes available when the VM starts."
                    : "Start the virtual machine to attach to its serial console."
            )
        }
    }

    // MARK: - Packages

    private var packagesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Packages") {
                if isActing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Packages are declarative. The hub writes them into configuration.nix and runs nixos-rebuild switch over SSH while the VM is running. Changes made while it is stopped apply on the next start.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                basePackageRow

                Divider().opacity(0.4)

                if machine.packages.isEmpty {
                    Text("No extra packages")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(machine.packages, id: \.self) { name in
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.accent)
                            Text(name)
                                .font(.system(size: 11, design: .monospaced))
                            Spacer()
                            if let guest, guest.reachable {
                                Text("installed")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                            Button {
                                removePackage(name)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(isActing || machine.status == .building)
                            .help("Remove \(name)")
                        }
                        Divider().opacity(0.3)
                    }
                }

                HStack(spacing: 6) {
                    TextField("Add a nixpkgs attribute, e.g. nodejs", text: $packageDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .onSubmit(addPackage)
                        .disabled(isActing || machine.status == .building)
                    Button("Add", action: addPackage)
                        .disabled(packageDraft.trimmingCharacters(in: .whitespaces).isEmpty || isActing || machine.status == .building)
                }

                if machine.hasPendingChanges {
                    NoticeRow(
                        icon: "arrow.triangle.2.circlepath",
                        message: machine.status == .running
                            ? "Changes are queued for the next apply."
                            : "Changes will be applied the next time NixOS boots.",
                        tint: Theme.warn
                    )
                }

                if machine.status == .running, machine.network.reachable, !machine.hasPendingChanges {
                    Button {
                        Task { await model.control(api: state.api, machine: machine, action: "apply") }
                    } label: {
                        Label("Re-apply configuration", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(isActing)
                }
            }
            .card()
        }
    }

    private var basePackageRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BASE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            FlowChips(items: ["curl", "git", "htop", "vim"], tint: .secondary)
        }
    }

    // MARK: - Logs

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Logs") {
                HStack(spacing: 8) {
                    Button {
                        Task { await loadLog() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reload this log")

                    Button {
                        copy(currentLog?.lines.joined(separator: "\n") ?? "")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Copy this log")
                }
            }

            Picker("", selection: $logType) {
                ForEach(VMLogType.allCases) { type in
                    Text(type.title).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .onChange(of: logType) { _, _ in
                Task { await loadLog() }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(currentLog?.path ?? "—")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let log = currentLog {
                        Text("\(log.lines.count) lines · \(Fmt.bytes(Int64(log.bytes)))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                ScrollView(.vertical) {
                    Text(currentLog?.lines.isEmpty == false
                        ? currentLog!.lines.joined(separator: "\n")
                        : "Nothing here yet.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 260)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.22))
                )

                if currentLog?.truncated == true {
                    Text("Showing the end of the log.")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
        .task(id: logType) {
            await loadLog()
        }
    }

    // MARK: - Helpers

    private var currentLog: VMLog? {
        model.log(for: machine.id, type: logType)
    }

    private var statusColor: Color {
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
        if let guest, let used = guest.memoryUsedBytes {
            return Fmt.bytes(used)
        }
        return "\(machine.memoryMB / 1_024) GB"
    }

    private var memoryCaption: String {
        if let guest, let total = guest.memoryTotalBytes {
            return "of \(Fmt.bytes(total))"
        }
        return "configured"
    }

    private var diskValue: String {
        if let guest, let used = guest.diskUsedBytes {
            return Fmt.bytes(used)
        }
        if let host, let used = host.diskUsedBytes {
            return Fmt.bytes(used)
        }
        return "—"
    }

    private var diskCaption: String {
        if let guest, let total = guest.diskTotalBytes {
            return "of \(Fmt.bytes(total))"
        }
        if let host, let total = host.diskBytes {
            return "of \(Fmt.bytes(total)) image"
        }
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

    private var loadValue: String {
        guard let guest, let one = guest.load1 else { return "—" }
        let five = guest.load5 ?? one
        let fifteen = guest.load15 ?? five
        return String(format: "%.2f  %.2f  %.2f", one, five, fifteen)
    }

    private func generationLabel(_ generation: String) -> String {
        let name = (generation as NSString).lastPathComponent
        return name.isEmpty ? generation : name
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private func infoRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: mono ? 9 : 10, weight: .regular, design: mono ? .monospaced : .default))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    private func addPackage() {
        let name = packageDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !machine.packages.contains(name) else { return }
        packageDraft = ""
        updatePackages(machine.packages + [name])
    }

    private func removePackage(_ name: String) {
        updatePackages(machine.packages.filter { $0 != name })
    }

    private func updatePackages(_ packages: [String]) {
        Task {
            await model.update(api: state.api, machine: machine, packages: packages)
        }
    }

    private func loadLog() async {
        guard let api = state.api else { return }
        await model.loadLog(api: api, machine: machine, type: logType)
    }

    private func loadBuildLogIfNeeded() async {
        guard let api = state.api else { return }
        if machine.status == .building || machine.status == .error || machine.progress != nil {
            await model.loadLog(api: api, machine: machine, type: .build, tail: 120)
        }
    }
}

