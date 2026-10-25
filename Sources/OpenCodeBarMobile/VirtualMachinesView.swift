import SwiftUI

/// Phone counterpart of the Mac VMs tab. The same hub API and store drive the
/// list; the detail page adds the console and package editor.
struct VirtualMachinesView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = VirtualMachinesStore()

    @State private var path = NavigationPath()
    @State private var showingCreate = false
    @State private var showingSetupLogs = false
    @State private var pendingDelete: VirtualMachine?
    @State private var openedRequestedVM = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !settings.isConfigured {
                        MobileVMNeedsPairing()
                    } else {
                        header
                        if let capabilities = model.capabilities, !capabilities.ready {
                            VMSetupRunnerCard(
                                capabilities: capabilities,
                                model: model,
                                api: store.api,
                                onViewLogs: { showingSetupLogs = true }
                            )
                        }
                        if let error = model.error, !model.machines.isEmpty {
                            NoticeRow(
                                icon: "exclamationmark.triangle.fill",
                                message: error,
                                tint: Theme.warn
                            )
                        }
                        content
                    }
                }
                .padding(16)
            }
            .mobileScreenBackground()
            .navigationTitle("Virtual Machines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSetupLogs = true
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                    }
                    .accessibilityLabel("Setup logs")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                    .disabled(model.capabilities?.ready != true || !settings.isConfigured)
                    .accessibilityLabel("Create a virtual machine")
                }
            }
            .refreshable { await model.tick(api: store.api) }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await poll()
            }
            .task(id: model.fetchedAt) {
                openRequestedVMIfNeeded()
            }
            .navigationDestination(for: String.self) { id in
                VirtualMachineMobileDetailView(machineID: id, model: model)
            }
            .sheet(isPresented: $showingCreate) {
                MobileNewVirtualMachineSheet(model: model) { machine in
                    path.append(machine.id)
                }
            }
            .sheet(isPresented: $showingSetupLogs) {
                VMSetupLogSheet(api: store.api)
            }
            .confirmationDialog(
                "Delete “\(pendingDelete?.name ?? "VM")”?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete VM and disk", role: .destructive) {
                    guard let machine = pendingDelete else { return }
                    pendingDelete = nil
                    Task { await model.remove(api: store.api, machine: machine, force: true) }
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The disk image, SSH key, logs, and all data inside the guest are removed.")
            }
        }
    }

    // MARK: - Content

    private var header: some View {
        SectionHeader("Machines") {
            HStack(spacing: 9) {
                if model.isRefreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                if model.runningCount > 0 {
                    Text("\(model.runningCount) running")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.running)
                        .monospacedDigit()
                }
                Text("\(model.machines.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.machines.isEmpty {
            if model.capabilities == nil && model.isRefreshing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Checking Virtualization.framework and Nix…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .card()
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
                    subtitle: "Create a NixOS guest. The hub builds the image, boots it with Virtualization.framework, and applies packages over SSH."
                )
            }
        } else {
            VStack(spacing: 9) {
                ForEach(sortedMachines) { machine in
                    NavigationLink(value: machine.id) {
                        MobileVirtualMachineRow(machine: machine)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = machine
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            Task {
                                await model.control(
                                    api: store.api,
                                    machine: machine,
                                    action: machine.status == .stopped || machine.status == .error
                                        ? "start" : "stop"
                                )
                            }
                        } label: {
                            Label(
                                machine.isRunning ? "Stop" : "Start",
                                systemImage: machine.isRunning ? "stop.fill" : "play.fill"
                            )
                        }
                        .tint(machine.isRunning ? Theme.danger : Theme.accent)
                    }
                }
            }

            if let fetched = model.fetchedAt {
                Text("Updated \(Fmt.relative(from: fetched))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
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

    private func poll() async {
        while !Task.isCancelled {
            await model.tick(api: store.api)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    #if DEBUG
    /// Screenshot helper: `OPENCODEBAR_OPEN_VM=<id-or-name>` opens a VM after
    /// the first list fetch, matching the session/project tooling.
    private func openRequestedVMIfNeeded() {
        guard !openedRequestedVM,
              path.isEmpty,
              let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_OPEN_VM"],
              let machine = model.machines.first(where: {
                  $0.id == requested || $0.name == requested
              })
        else { return }
        openedRequestedVM = true
        path.append(machine.id)
    }
    #else
    private func openRequestedVMIfNeeded() {}
    #endif
}

private struct MobileVirtualMachineRow: View {
    let machine: VirtualMachine

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: "server.rack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(machine.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Chip(text: machine.status.label, tint: statusColor)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    Text("\(machine.cpuCount) CPU · \(machine.memoryMB / 1_024) GB")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let ip = machine.network.ip {
                        Text(ip)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(machine.network.reachable ? Theme.accent : .secondary)
                            .lineLimit(1)
                    }
                }

                if let progress = machine.progress {
                    Text(progress.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let error = machine.lastError, machine.status == .error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Theme.danger)
                        .lineLimit(2)
                } else if machine.hasPendingPackages {
                    Text("Package changes pending")
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                }
            }
        }
        .padding(11)
        .card(padding: 0)
        .contentShape(Rectangle())
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
}

private struct MobileVMNeedsPairing: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "server.rack")
                    .font(.title3.weight(.light))
                    .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pair with your hub")
                        .font(.subheadline.weight(.semibold))
                    Text("Virtual machines live on the Mac that runs the hub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Open Settings and scan the pairing QR code, or paste the hub URL and token.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }
}
