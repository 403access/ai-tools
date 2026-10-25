import Foundation
import SwiftTerm

/// Drives a guest's serial console over the hub's WebSocket proxy.
///
/// Unlike a PTY there is no cursor or resize protocol: the helper replays the
/// last chunk of the boot log and then streams raw bytes. Input goes back as
/// text and lands on the guest's serial port.
@MainActor
final class VMConsoleConnection: ObservableObject, TerminalSession {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected(String)

        var label: String {
            switch self {
            case .idle: return "Ready"
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .disconnected(let reason): return reason.isEmpty ? "Disconnected" : reason
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    let api: HubAPI
    let machineID: String

    @Published private(set) var state: State = .idle

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var pending: [UInt8] = []
    private weak var terminalView: SwiftTerm.TerminalView?

    init(api: HubAPI, machineID: String) {
        self.api = api
        self.machineID = machineID
    }

    func attach(_ view: SwiftTerm.TerminalView) {
        terminalView = view
        if !pending.isEmpty {
            view.feed(byteArray: pending[...])
            pending.removeAll(keepingCapacity: true)
        }
        if state == .idle {
            connect()
        }
    }

    func detach(_ view: SwiftTerm.TerminalView) {
        guard terminalView === view else { return }
        terminalView = nil
    }

    func connect() {
        guard socket == nil else { return }
        state = .connecting
        do {
            let request = try api.virtualMachineConsoleRequest(id: machineID)
            let socket = URLSession.shared.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            receiveTask = Task { [weak self] in
                await self?.receiveLoop(socket)
            }
        } catch {
            state = .disconnected(message(for: error))
        }
    }

    func disconnect() {
        receiveTask?.cancel()
        receiveTask = nil
        sendTask?.cancel()
        sendTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if state == .connecting || state.isConnected {
            state = .disconnected("Disconnected")
        }
    }

    func send(_ data: ArraySlice<UInt8>) {
        guard !data.isEmpty, socket != nil else { return }
        enqueueSend(String(decoding: data, as: UTF8.self))
    }

    /// The serial line does not carry terminal geometry. SwiftTerm still asks,
    /// so accept the values and leave the guest's default 80×24 in place.
    func resize(cols: Int, rows: Int) {}

    private func enqueueSend(_ text: String) {
        let previous = sendTask
        sendTask = Task { [weak self] in
            _ = await previous?.value
            guard let self, let socket = self.socket else { return }
            try? await socket.send(.string(text))
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let message = try await socket.receive()
                if state == .connecting {
                    state = .connected
                }
                switch message {
                case .string(let text):
                    feed(Data(text.utf8))
                case .data(let data):
                    feed(data)
                @unknown default:
                    break
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            if self.socket === socket {
                self.socket = nil
                state = .disconnected(message(for: error))
            }
        }
    }

    private func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        if let terminalView {
            terminalView.feed(byteArray: [UInt8](data)[...])
        } else {
            pending.append(contentsOf: data)
            if pending.count > 1_048_576 {
                pending.removeFirst(pending.count - 1_048_576)
            }
        }
    }

    private func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? String(describing: apiError)
        }
        return error.localizedDescription
    }
}
