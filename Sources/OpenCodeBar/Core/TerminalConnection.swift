import Foundation
import SwiftTerm

/// Drives one terminal session over the hub's WebSocket proxy.
///
/// OpenCode sends raw terminal output as text frames and one binary control
/// frame after the replay buffer (`0x00` followed by `{"cursor": …}`). Input is
/// sent back as text, and resizing goes over HTTP because normal PTYs do not
/// carry resize frames on the socket.
@MainActor
final class TerminalConnection: ObservableObject {
    enum State: Equatable {
        case connecting
        case connected
        case disconnected(String)
        case exited

        var label: String {
            switch self {
            case .connecting: return "Connecting…"
            case .connected: return "Connected"
            case .disconnected(let reason): return reason.isEmpty ? "Disconnected" : reason
            case .exited: return "Process exited"
            }
        }

        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    let api: HubAPI
    let terminal: SystemTerminal

    @Published private(set) var state: State
    /// Absolute output position of the last replay, used when reconnecting.
    @Published private(set) var cursor: Int?

    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var resizeTask: Task<Void, Never>?
    private var pendingOutput: [UInt8] = []
    private var pendingSize: TerminalSize?
    /// True until the replay boundary arrives. Replayed output is already
    /// counted by the cursor control frame, so live output is the only output
    /// this client adds to the absolute position.
    private var awaitingReplayCursor = false
    private weak var terminalView: SwiftTerm.TerminalView?

    init(api: HubAPI, terminal: SystemTerminal) {
        self.api = api
        self.terminal = terminal
        self.state = terminal.isRunning ? .connecting : .exited
    }

    /// Called by the representable once SwiftTerm's view exists. Output that
    /// arrived before the view was ready is replayed into it.
    func attach(_ view: SwiftTerm.TerminalView) {
        terminalView = view
        if !pendingOutput.isEmpty {
            view.feed(byteArray: pendingOutput[...])
            pendingOutput.removeAll(keepingCapacity: true)
        }
        if terminal.isRunning, state == .connecting {
            connect()
        }
    }

    func detach(_ view: SwiftTerm.TerminalView) {
        guard terminalView === view else { return }
        terminalView = nil
    }

    func connect() {
        guard terminal.isRunning else {
            state = .exited
            return
        }
        guard socket == nil else { return }

        state = .connecting
        awaitingReplayCursor = true
        do {
            let request = try api.terminalSocketRequest(
                id: terminal.id,
                location: terminal.location,
                cursor: cursor
            )
            let socket = URLSession.shared.webSocketTask(with: request)
            self.socket = socket
            socket.resume()
            receiveTask = Task { [weak self] in
                await self?.receiveLoop(socket)
            }
        } catch {
            awaitingReplayCursor = false
            state = .disconnected(message(for: error))
        }
    }

    /// Leaves the shell running on the host while closing this connection.
    func disconnect() {
        resizeTask?.cancel()
        resizeTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        sendTask?.cancel()
        sendTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if state.isConnected || state == .connecting {
            state = .disconnected("Disconnected")
        }
    }

    /// Forwards bytes produced by the terminal view (keys, paste, control
    /// sequences) to the shell.
    func send(_ data: ArraySlice<UInt8>) {
        guard !data.isEmpty, socket != nil else { return }
        enqueueSend(String(decoding: data, as: UTF8.self))
    }

    /// Runs one line and its Enter key. Used by the compact command field.
    func submit(_ line: String) {
        guard socket != nil else { return }
        enqueueSend(line + "\r")
    }

    /// SwiftTerm reports a new grid size whenever the view lays out; OpenCode
    /// applies the size through its HTTP update route.
    func resize(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        guard pendingSize != TerminalSize(rows: rows, cols: cols) else { return }
        pendingSize = TerminalSize(rows: rows, cols: cols)

        resizeTask?.cancel()
        resizeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushSize()
        }
    }

    private func flushSize() async {
        guard let size = pendingSize, terminal.isRunning else { return }
        resizeTask = nil
        _ = try? await api.updateTerminal(
            id: terminal.id,
            size: size,
            location: terminal.location
        )
    }

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
                handle(message)
            }
        } catch {
            guard !Task.isCancelled else { return }
            if self.socket === socket {
                self.socket = nil
                state = .disconnected(message(for: error))
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            advanceCursor(with: text)
            feed(Data(text.utf8))
        case .data(let data):
            if data.first == 0 {
                updateCursor(from: data.dropFirst())
            } else {
                if let text = String(data: data, encoding: .utf8) {
                    advanceCursor(with: text)
                }
                feed(data)
            }
        @unknown default:
            break
        }
    }

    /// OpenCode counts the cursor in UTF-16 code units, so the position can be
    /// carried forward after the replay without another control frame.
    private func advanceCursor(with text: String) {
        guard !awaitingReplayCursor else { return }
        cursor = (cursor ?? 0) + text.utf16.count
    }

    private func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        if let terminalView {
            terminalView.feed(byteArray: [UInt8](data)[...])
        } else {
            pendingOutput.append(contentsOf: data)
            // The view attaches immediately in practice; keep the buffer
            // bounded in case a sheet is slow to present.
            if pendingOutput.count > 1_048_576 {
                pendingOutput.removeFirst(pendingOutput.count - 1_048_576)
            }
        }
    }

    private func updateCursor(from data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object["cursor"] as? NSNumber
        else { return }
        cursor = value.intValue
        awaitingReplayCursor = false
    }

    private func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.errorDescription ?? String(describing: apiError)
        }
        return error.localizedDescription
    }
}
