import Foundation

private struct ControlRequest: Decodable {
    let id: Int
    let op: String
    let force: Bool?
}

/// JSON-lines control channel for the hub.
///
/// Each request is `{"id": 1, "op": "status"}` and each response carries the
/// same id plus either `result` or `error`. Requests that touch the VM hop to
/// the main actor; socket I/O stays on its own serial queue.
final class ControlServer {
    private let runner: VMRunner
    private let queue = DispatchQueue(label: "opencodebar.vz.control")
    private var listener: LoopbackServer?
    private var clients: [Int32: ClientConnection] = [:]
    private(set) var port = 0

    init(runner: VMRunner) {
        self.runner = runner
    }

    func start() throws {
        let listener = LoopbackServer(label: "opencodebar.vz.control.listen") { [weak self] fd in
            self?.accept(fd)
        }
        try listener.start()
        self.listener = listener
        port = listener.port
    }

    func stop() {
        listener?.stop()
        listener = nil
        queue.sync {
            for client in clients.values { client.close() }
            clients.removeAll()
        }
    }

    private func accept(_ fd: Int32) {
        queue.async { [weak self] in
            guard let self else { return }
            var buffer = Data()
            let client = ClientConnection(
                fd: fd,
                queue: self.queue,
                onData: { _ in },
                onClose: { [weak self] in
                    self?.clients.removeValue(forKey: fd)
                }
            )
            client.onData = { [weak self, weak client] chunk in
                guard let self, let client else { return }
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[..<newline]
                    buffer.removeSubrange(...newline)
                    if !line.isEmpty {
                        self.handle(Data(line), on: client)
                    }
                }
            }
            self.clients[fd] = client
            client.start()
        }
    }

    private func handle(_ line: Data, on client: ClientConnection) {
        guard let request = try? JSONDecoder().decode(ControlRequest.self, from: line) else {
            respond(client, id: 0, error: "Malformed request")
            return
        }

        Task { @MainActor in
            do {
                let result: [String: Any]
                switch request.op {
                case "status":
                    result = self.runner.statusPayload
                case "start":
                    try await self.runner.start()
                    result = self.runner.statusPayload
                case "stop":
                    try await self.runner.stop(force: request.force ?? false)
                    result = self.runner.statusPayload
                case "pause":
                    try await self.runner.pause()
                    result = self.runner.statusPayload
                case "resume":
                    try await self.runner.resume()
                    result = self.runner.statusPayload
                default:
                    self.respond(client, id: request.id, error: "Unknown operation: \(request.op)")
                    return
                }
                self.respond(client, id: request.id, result: result)
            } catch {
                self.respond(
                    client,
                    id: request.id,
                    error: error.localizedDescription
                )
            }
        }
    }

    private func respond(
        _ client: ClientConnection,
        id: Int,
        result: [String: Any]? = nil,
        error: String? = nil
    ) {
        var payload: [String: Any] = ["id": id, "ok": error == nil]
        if let result { payload["result"] = result }
        if let error { payload["error"] = error }
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var line = data
        line.append(0x0A)
        client.write(line)
    }
}
