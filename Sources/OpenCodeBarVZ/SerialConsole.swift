import Foundation

/// Bridges the guest's virtual serial port to a raw TCP socket and a log file.
///
/// Virtualization.framework writes guest output into `outputPipe.fileHandleForWriting`
/// and reads keyboard input from `inputPipe.fileHandleForReading`. The other
/// ends stay in this process, so the helper can broadcast output and write any
/// client's bytes back to the guest.
final class SerialConsole {
    private let logPath: String
    private let queue = DispatchQueue(label: "opencodebar.vz.serial")
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private var listener: LoopbackServer?
    private var clients: [Int32: ClientConnection] = [:]
    private var logHandle: FileHandle?
    private(set) var port = 0

    /// The VM reads host input from this handle.
    var guestInputRead: FileHandle { inputPipe.fileHandleForReading }
    /// The VM writes guest output to this handle.
    var guestOutputWrite: FileHandle { outputPipe.fileHandleForWriting }

    init(logPath: String) {
        self.logPath = logPath
    }

    func start() throws {
        try FileSupport.ensureDirectory((logPath as NSString).deletingLastPathComponent)
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: logPath)
        let handle = FileHandle(forWritingAtPath: logPath)
        handle?.seekToEndOfFile()
        logHandle = handle

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else { return }
            self.queue.async { self.broadcast(data) }
        }

        let listener = LoopbackServer(label: "opencodebar.vz.serial.listen") { [weak self] fd in
            self?.accept(fd)
        }
        try listener.start()
        self.listener = listener
        port = listener.port
    }

    func stop() {
        outputPipe.fileHandleForReading.readabilityHandler = nil
        listener?.stop()
        listener = nil
        queue.sync {
            for client in clients.values { client.close() }
            clients.removeAll()
            try? logHandle?.close()
            logHandle = nil
        }
    }

    private func accept(_ fd: Int32) {
        queue.async { [weak self] in
            guard let self else { return }
            let replay = self.logTail()
            let client = ClientConnection(
                fd: fd,
                queue: self.queue,
                onData: { [weak self] data in
                    self?.queue.async {
                        try? self?.inputPipe.fileHandleForWriting.write(contentsOf: data)
                    }
                },
                onClose: { [weak self] in
                    self?.clients.removeValue(forKey: fd)
                }
            )
            self.clients[fd] = client
            client.start()
            if !replay.isEmpty { client.write(replay) }
        }
    }

    private func broadcast(_ data: Data) {
        try? logHandle?.write(contentsOf: data)
        for client in clients.values {
            client.write(data)
        }
    }

    /// Sends the last 64 KiB so opening the console shows the boot log rather
    /// than a blank screen.
    private func logTail() -> Data {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: logPath)) else {
            return Data()
        }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let limit: UInt64 = 64 * 1024
        let start = size > limit ? size - limit : 0
        try? handle.seek(toOffset: start)
        return (try? handle.readToEnd()) ?? Data()
    }
}
