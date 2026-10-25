import SwiftUI

/// Top-level VM list. Polls the hub every few seconds, keeps the selected VM
/// open on its own detail page, and explains missing host prerequisites instead
/// of failing at create time.
struct VirtualMachinesTab: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var model = VirtualMachinesStore()

    @State private var showingCreate = false
    @State private var showingSetupLogs = false
    @State private var setupLogStep: VMSetupStep = .nix
    @State private var pendingDelete: VirtualMachine?
    @State private var pendingRebuild: VirtualMachine?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let machine = model.selected {
                VirtualMachineDetailView(
                    machine: machine,
                    model: model,
                    onBack: { model.selectedID = nil },
                    onDelete: { pendingDelete = machine },
                    onRebuild: { pendingRebuild = machine }
                )
            } else {
                listView
            }
        }
        .task { await poll() }
        .sheet(isPresented: $showingCreate) {
            NewVirtualMachineSheet(model: model)
        }
        .sheet(isPresented: $showingSetupLogs) {
            VMSetupLogSheet(api: state.api, initialStep: setupLogStep)
        }
        .alert(item: $pendingDelete) { machine in
            Alert(
                title: Text("Delete “\(machine.name)”?"),
                message: Text("The VM, its disk image, SSH key, and logs will be removed. This cannot be undone."),
                primaryButton: .destructive(Text("Delete VM and disk")) {
                    Task { await model.remove(api: state.api, machine: machine, force: true) }
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $pendingRebuild) { machine in
            Alert(
                title: Text("Rebuild “\(machine.name)”?"),
                message: Text("Rebuilding replaces the guest disk and loses everything installed or saved inside NixOS. Extra packages in the hub definition are preserved."),
                primaryButton: .destructive(Text("Replace the disk")) {
                    Task {
                        await model.control(api: state.api, machine: machine, action: "rebuild", force: true)
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - List

    private var listView: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let capabilities = model.capabilities, !capabilities.ready {
                VMSetupRunnerCard(
                    capabilities: capabilities,
                    model: model,
                    api: state.api,
                    onViewLogs: {
                        setupLogStep = .nix
                        showingSetupLogs = true
                    }
                )
            }

            if let capabilities = model.capabilities, capabilities.linuxBuilder {
                VMLinuxBuilderCard(capabilities: capabilities) {
                    setupLogStep = .builder
                    showingSetupLogs = true
                }
            }

            if let error = model.error, !model.machines.isEmpty {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            }

            if model.machines.isEmpty {
                if model.capabilities == nil && model.isRefreshing {
                    loadingCard
                } else if let error = model.error {
                    EmptyState(
                        icon: "server.rack",
                        title: "Virtual machines unavailable",
                        subtitle: error
                    )
                } else if model.capabilities?.ready == true {
                    EmptyState(
                        icon: "server.rack",
                        title: "No virtual machines",
                        subtitle: "Create a NixOS guest. The hub builds a raw EFI image, runs it with Virtualization.framework, and applies package changes over SSH."
                    )
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedMachines) { machine in
                        VirtualMachineRow(machine: machine) {
                            model.selectedID = machine.id
                        } onStart: {
                            Task {
                                await model.control(
                                    api: state.api,
                                    machine: machine,
                                    action: machine.status == .stopped || machine.status == .error ? "start" : "stop"
                                )
                            }
                        }
                    }
                }
            }

            footer
        }
    }

    private var header: some View {
        SectionHeader("Virtual Machines") {
            HStack(spacing: 8) {
                if model.isRefreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                }
                if model.runningCount > 0 {
                    Text("\(model.runningCount) running")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.running)
                        .monospacedDigit()
                }
                Button {
                    setupLogStep = .nix
                    showingSetupLogs = true
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Setup logs")

                Button {
                    Task { await model.refresh(api: state.api) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh virtual machines")

                Button {
                    showingCreate = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Create a NixOS virtual machine")
                .disabled(model.capabilities?.ready != true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(model.capabilities?.storageDir ?? "—")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            if let fetched = model.fetchedAt {
                Text("Updated \(Fmt.relative(from: fetched))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            Text("Checking Virtualization.framework and Nix…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private var sortedMachines: [VirtualMachine] {
        model.machines.sorted { left, right in
            let leftRank = rank(left.status)
            let rightRank = rank(right.status)
            if leftRank != rightRank { return leftRank < rightRank }
            return left.createdAt > right.createdAt
        }
    }

    private func rank(_ status: VirtualMachine.Status) -> Int {
        switch status {
        case .running: return 0
        case .starting, .building: return 1
        case .paused: return 2
        case .stopping: return 3
        case .error: return 4
        case .stopped, .unknown: return 5
        }
    }

    // MARK: - Polling

    private func poll() async {
        while !Task.isCancelled {
            await model.tick(api: state.api)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
}

struct VirtualMachineRow: View {
    let machine: VirtualMachine
    let onOpen: () -> Void
    let onStart: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onOpen) {
                HStack(spacing: 9) {
                    statusDot

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(machine.name)
                                .font(.system(size: 12, weight: .semibold))
                                .lineLimit(1)
                            Chip(
                                text: machine.status.label,
                                systemImage: statusIcon,
                                tint: statusColor
                            )
                            Spacer(minLength: 4)
                            Text("\(machine.cpuCount) CPU · \(machine.memoryMB / 1_024) GB")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        HStack(spacing: 6) {
                            Text("NixOS · \(machine.channel)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let ip = machine.network.ip {
                                Text(ip)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(machine.network.reachable ? Theme.accent : .secondary)
                                    .lineLimit(1)
                            }
                            if machine.hasPendingPackages {
                                Text("packages pending")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Theme.warn)
                            }
                        }

                        if let progress = machine.progress {
                            Text(progress.message)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else if let error = machine.lastError, machine.status == .error {
                            Text(error)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.danger)
                                .lineLimit(2)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onStart) {
                Image(systemName: startIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(machine.isRunning ? Theme.accent : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(machine.isRunning ? "Stop" : "Start")
            .disabled(machine.isBusy)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .onHover { hovering = $0 }
    }

    private var startIcon: String {
        if machine.isRunning { return "stop.fill" }
        if machine.isBusy { return "hourglass" }
        return "play.fill"
    }

    private var statusDot: some View {
        Group {
            if machine.isRunning {
                PulsingDot(color: statusColor, size: 6)
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .frame(width: 12, height: 12)
            }
        }
    }

    private var statusColor: Color {
        switch machine.status {
        case .running: return Theme.running
        case .starting, .building, .stopping: return Theme.warn
        case .paused: return Theme.reasoning
        case .error: return Theme.danger
        case .stopped, .unknown: return .secondary.opacity(0.55)
        }
    }

    private var statusIcon: String? {
        switch machine.status {
        case .running: return "play.fill"
        case .building: return "hammer.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .paused: return "pause.fill"
        default: return nil
        }
    }
}
