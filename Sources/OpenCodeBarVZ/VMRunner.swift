import Foundation
import Virtualization

enum VMRunnerError: LocalizedError {
    case notRunning
    case notPaused
    case invalidMAC(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "The virtual machine is not running"
        case .notPaused: return "The virtual machine is not paused"
        case .invalidMAC(let value): return "Invalid MAC address: \(value)"
        }
    }
}

/// Owns one `VZVirtualMachine`.
///
/// All mutation happens on the main actor. Virtualization's completion handlers
/// can arrive on another queue, so the delegate methods hop back to the main
/// actor before touching state.
@MainActor
final class VMRunner: NSObject, VZVirtualMachineDelegate {
    private let config: VMConfig
    private nonisolated(unsafe) let serial: SerialConsole
    private var machine: VZVirtualMachine?
    private var startedAt: Int64?
    private var lastError: String?
    private var starting = false

    nonisolated init(config: VMConfig, serial: SerialConsole) {
        self.config = config
        self.serial = serial
        super.init()
    }

    var stateString: String {
        guard let machine else { return "stopped" }
        switch machine.state {
        case .stopped: return "stopped"
        case .running: return "running"
        case .paused: return "paused"
        case .error: return "error"
        case .starting: return "starting"
        case .pausing: return "pausing"
        case .resuming: return "resuming"
        case .stopping: return "stopping"
        case .saving: return "saving"
        case .restoring: return "restoring"
        @unknown default: return "stopped"
        }
    }

    var statusPayload: [String: Any] {
        var payload: [String: Any] = [
            "state": stateString,
            "pid": Int(getpid()),
        ]
        if let startedAt { payload["startedAt"] = startedAt }
        if let lastError { payload["error"] = lastError }
        return payload
    }

    // MARK: - Lifecycle

    func start() async throws {
        if let machine, machine.state == .running { return }
        if starting { throw VMRunnerError.notRunning }
        starting = true
        defer { starting = false }

        if machine == nil {
            machine = try makeMachine()
        }
        guard let machine else { throw VMRunnerError.notRunning }

        if machine.state == .paused {
            try await resume()
            return
        }

        try await machine.start()
        startedAt = FileSupport.nowMillis()
        lastError = nil
    }

    func stop(force: Bool) async throws {
        guard let machine, machine.state != .stopped else { return }

        if force {
            try await stopImmediately(machine)
        } else {
            do {
                try await requestStop(machine)
                let deadline = Date().addingTimeInterval(30)
                while machine.state != .stopped && Date() < deadline {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                if machine.state != .stopped {
                    try await stopImmediately(machine)
                }
            } catch {
                try await stopImmediately(machine)
            }
        }
        startedAt = nil
    }

    func pause() async throws {
        guard let machine, machine.state == .running else { throw VMRunnerError.notRunning }
        try await machine.pause()
    }

    func resume() async throws {
        guard let machine, machine.state == .paused else { throw VMRunnerError.notPaused }
        try await machine.resume()
    }

    func shutdown() async {
        try? await stop(force: true)
        serial.stop()
    }

    private func requestStop(_ machine: VZVirtualMachine) async throws {
        // `requestStopWithError:` is synchronous: it asks the guest to shut
        // down and reports whether the request could be delivered.
        try machine.requestStop()
    }

    private func stopImmediately(_ machine: VZVirtualMachine) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            machine.stop { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Configuration

    private func makeMachine() throws -> VZVirtualMachine {
        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = max(1, config.cpuCount)
        configuration.memorySize = config.memoryBytes

        let platform = VZGenericPlatformConfiguration()
        let identifierURL = URL(fileURLWithPath: config.machineIdentifier)
        if let data = try? Data(contentsOf: identifierURL),
           let identifier = VZGenericMachineIdentifier(dataRepresentation: data) {
            platform.machineIdentifier = identifier
        } else {
            let identifier = VZGenericMachineIdentifier()
            platform.machineIdentifier = identifier
            try FileSupport.ensureDirectory(
                (config.machineIdentifier as NSString).deletingLastPathComponent
            )
            try? identifier.dataRepresentation.write(to: identifierURL)
        }
        configuration.platform = platform

        let bootLoader = VZEFIBootLoader()
        let variableStoreURL = URL(fileURLWithPath: config.efiVariableStore)
        if FileManager.default.fileExists(atPath: config.efiVariableStore) {
            bootLoader.variableStore = VZEFIVariableStore(url: variableStoreURL)
        } else {
            try FileSupport.ensureDirectory(
                (config.efiVariableStore as NSString).deletingLastPathComponent
            )
            bootLoader.variableStore = try VZEFIVariableStore(
                creatingVariableStoreAt: variableStoreURL
            )
        }
        configuration.bootLoader = bootLoader

        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        configuration.memoryBalloonDevices = [
            VZVirtioTraditionalMemoryBalloonDeviceConfiguration()
        ]

        let network = VZVirtioNetworkDeviceConfiguration()
        guard let mac = VZMACAddress(string: config.macAddress) else {
            throw VMRunnerError.invalidMAC(config.macAddress)
        }
        network.macAddress = mac
        network.attachment = VZNATNetworkDeviceAttachment()
        configuration.networkDevices = [network]

        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: URL(fileURLWithPath: config.diskPath),
            readOnly: false
        )
        configuration.storageDevices = [
            VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
        ]

        let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
        serialPort.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: serial.guestInputRead,
            fileHandleForWriting: serial.guestOutputWrite
        )
        configuration.serialPorts = [serialPort]

        try configuration.validate()
        let machine = VZVirtualMachine(configuration: configuration)
        machine.delegate = self
        return machine
    }

    // MARK: - VZVirtualMachineDelegate

    nonisolated func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        Task { @MainActor in
            self.startedAt = nil
            self.lastError = nil
        }
    }

    nonisolated func virtualMachine(
        _ virtualMachine: VZVirtualMachine,
        didStopWithError error: Error
    ) {
        Task { @MainActor in
            self.startedAt = nil
            self.lastError = error.localizedDescription
        }
    }
}
