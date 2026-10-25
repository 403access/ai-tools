import Foundation

/// Shared state for the VMs tab on macOS and iOS.
///
/// The store is deliberately API-injected: both apps already own a `HubAPI`
/// that reconnects when the hub moves, so the view passes the current client on
/// each poll instead of caching a stale one.
@MainActor
final class VirtualMachinesStore: ObservableObject {
    @Published private(set) var machines: [VirtualMachine] = []
    @Published private(set) var capabilities: VMCapabilities?
    @Published private(set) var isLoading = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var fetchedAt: Date?
    @Published private(set) var error: String?
    @Published private(set) var logs: [String: VMLog] = [:]
    @Published private(set) var actionsInFlight: Set<String> = []
    @Published private(set) var setup: VMSetupJob?
    @Published var selectedID: String?

    private var capabilitiesFetchedAt: Date?

    var selected: VirtualMachine? {
        guard let selectedID else { return nil }
        return machines.first { $0.id == selectedID }
    }

    var runningCount: Int {
        machines.filter(\.isRunning).count
    }

    func machine(_ id: String) -> VirtualMachine? {
        machines.first { $0.id == id }
    }

    func log(for id: String, type: VMLogType) -> VMLog? {
        logs[logKey(id, type)]
    }

    // MARK: - Polling

    func refresh(api: HubAPI?) async {
        guard let api else {
            error = "Not connected to the hub"
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let wantsCapabilities =
            capabilities == nil ||
            capabilitiesFetchedAt.map { Date().timeIntervalSince($0) > 30 } == true

        do {
            let list = try await api.virtualMachines()
            machines = list
            if let selectedID, !list.contains(where: { $0.id == selectedID }) {
                self.selectedID = nil
            }
            fetchedAt = Date()
            error = nil

            if wantsCapabilities {
                capabilities = try? await api.virtualMachineCapabilities()
                capabilitiesFetchedAt = Date()
            }
        } catch {
            self.error = message(for: error)
        }
    }

    func refreshSelected(api: HubAPI?) async {
        guard let api, let selectedID else { return }
        do {
            let machine = try await api.virtualMachine(id: selectedID, refresh: true)
            replace(machine)
        } catch {
            self.error = message(for: error)
        }
    }

    /// One poll tick used by both platforms: the list every time, a deeper
    /// metrics refresh for the open VM, and setup progress while host setup is
    /// incomplete or running.
    func tick(api: HubAPI?) async {
        await refresh(api: api)
        await refreshSelected(api: api)
        if capabilities?.ready != true || setup?.status == .running {
            await refreshSetup(api: api)
        }
    }

    // MARK: - Host setup

    func refreshSetup(api: HubAPI?) async {
        guard let api else { return }
        let previous = setup?.status
        do {
            let job = try await api.vmSetupStatus()
            setup = job
            if previous == .running, job?.status == .succeeded {
                // Drop the cached capabilities and fetch them again so the
                // setup card disappears as soon as Nix/helper is detected.
                capabilities = nil
                capabilitiesFetchedAt = nil
                await refresh(api: api)
            }
        } catch {
            // The setup card shows the job's own error; don't replace a working
            // VM list with a transient setup-poll failure.
            if setup == nil { self.error = message(for: error) }
        }
    }

    func startSetup(api: HubAPI?, step: VMSetupStep) async {
        guard let api else {
            error = "Not connected to the hub"
            return
        }
        let key = "setup:\(step.rawValue)"
        actionsInFlight.insert(key)
        defer { actionsInFlight.remove(key) }
        do {
            setup = try await api.startVMSetup(step: step)
            error = nil
        } catch {
            self.error = message(for: error)
        }
    }

    func cancelSetup(api: HubAPI?) async {
        guard let api else { return }
        do {
            setup = try await api.cancelVMSetup()
        } catch {
            self.error = message(for: error)
        }
    }

    // MARK: - Actions

    func create(
        api: HubAPI?,
        name: String,
        cpuCount: Int,
        memoryMB: Int,
        diskGB: Int,
        channel: String,
        packages: [String]
    ) async throws -> VirtualMachine {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        isLoading = true
        defer { isLoading = false }
        let machine = try await api.createVirtualMachine(
            name: name,
            cpuCount: cpuCount,
            memoryMB: memoryMB,
            diskGB: diskGB,
            channel: channel,
            packages: packages
        )
        replace(machine)
        selectedID = machine.id
        error = nil
        return machine
    }

    func control(
        api: HubAPI?,
        machine: VirtualMachine,
        action: String,
        force: Bool = false
    ) async {
        guard let api else {
            error = "Not connected to the hub"
            return
        }
        actionsInFlight.insert(machine.id)
        defer { actionsInFlight.remove(machine.id) }
        do {
            let updated = try await api.controlVirtualMachine(
                id: machine.id,
                action: action,
                force: force
            )
            replace(updated)
            error = nil
        } catch {
            self.error = message(for: error)
        }
    }

    func update(
        api: HubAPI?,
        machine: VirtualMachine,
        name: String? = nil,
        cpuCount: Int? = nil,
        memoryMB: Int? = nil,
        packages: [String]? = nil
    ) async {
        guard let api else {
            error = "Not connected to the hub"
            return
        }
        actionsInFlight.insert(machine.id)
        defer { actionsInFlight.remove(machine.id) }
        do {
            let updated = try await api.updateVirtualMachine(
                id: machine.id,
                name: name,
                cpuCount: cpuCount,
                memoryMB: memoryMB,
                packages: packages
            )
            replace(updated)
            error = nil
        } catch {
            self.error = message(for: error)
        }
    }

    func remove(api: HubAPI?, machine: VirtualMachine, force: Bool = false) async {
        guard let api else {
            error = "Not connected to the hub"
            return
        }
        actionsInFlight.insert(machine.id)
        defer { actionsInFlight.remove(machine.id) }
        do {
            try await api.deleteVirtualMachine(id: machine.id, force: force)
            machines.removeAll { $0.id == machine.id }
            if selectedID == machine.id { selectedID = nil }
            error = nil
        } catch {
            self.error = message(for: error)
        }
    }

    func loadLog(api: HubAPI?, machine: VirtualMachine, type: VMLogType, tail: Int = 240) async {
        guard let api else { return }
        do {
            let log = try await api.virtualMachineLog(id: machine.id, type: type, tail: tail)
            logs[logKey(machine.id, type)] = log
        } catch {
            self.error = message(for: error)
        }
    }

    func replace(_ machine: VirtualMachine) {
        if let index = machines.firstIndex(where: { $0.id == machine.id }) {
            machines[index] = machine
        } else {
            machines.insert(machine, at: 0)
        }
    }

    func clearError() {
        error = nil
    }

    private func logKey(_ id: String, _ type: VMLogType) -> String {
        "\(id):\(type.rawValue)"
    }

    private func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            if case .request(404, _) = apiError {
                return "This hub does not serve virtual machines yet. Restart it with the latest code."
            }
            return apiError.errorDescription ?? String(describing: apiError)
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
