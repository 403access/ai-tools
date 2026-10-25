import Foundation

/// Frames travel between the helper and the hub as:
///
///     [kind: UInt8][payloadLength: UInt32 big-endian][payload]
///
/// `status` and `log` payloads are UTF-8 JSON; `frame` payloads are a small
/// binary header followed by a JPEG. Keeping the transport this small means the
/// hub can stay a Bun process and relay frames without another dependency.
enum WireKind: UInt8 {
    case status = 1
    case frame = 2
    case log = 3
}

final class WireOutput: @unchecked Sendable {
    static let shared = WireOutput()

    private let lock = NSLock()
    private let handle = FileHandle.standardOutput
    private let started = ProcessInfo.processInfo.systemUptime
    private var sequence: UInt32 = 0

    func status(_ payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload)
        else { return }
        emit(.status, data)
    }

    func log(_ message: String, level: String = "info") {
        let payload: [String: Any] = [
            "type": "log",
            "level": level,
            "message": message,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            emit(.log, data)
        }
        FileHandle.standardError.write(Data(("[remote-host] \(message)\n").utf8))
    }

    /// Sends one JPEG. The sequence number lets clients drop a frame that
    /// arrives after a newer one, and the timestamp is useful for latency
    /// readouts in the app.
    func frame(jpeg: Data, width: Int, height: Int) {
        lock.lock()
        sequence &+= 1
        let seq = sequence
        lock.unlock()

        let timestamp = UInt32(
            truncatingIfNeeded: Int(
                (ProcessInfo.processInfo.systemUptime - started) * 1000
            )
        )

        var payload = Data(capacity: jpeg.count + 14)
        payload.append(0x52) // "R"
        payload.append(0x44) // "D"
        appendUInt32(seq, to: &payload)
        appendUInt32(timestamp, to: &payload)
        appendUInt16(UInt16(clamping: width), to: &payload)
        appendUInt16(UInt16(clamping: height), to: &payload)
        payload.append(jpeg)
        emit(.frame, payload)
    }

    private func emit(_ kind: WireKind, _ payload: Data) {
        var message = Data(capacity: payload.count + 5)
        message.append(kind.rawValue)
        appendUInt32(UInt32(clamping: payload.count), to: &message)
        message.append(payload)

        lock.lock()
        do {
            try handle.write(contentsOf: message)
        } catch {
            // The hub went away; there is nowhere left to report this.
        }
        lock.unlock()
    }
}

enum WireInput {
    private static let reads = DispatchQueue(
        label: "dev.opencodebar.remote.stdin",
        qos: .userInitiated
    )
    private static var source: DispatchSourceRead?
    private static var buffer = Data()

    /// Reads newline-delimited commands with a dispatch read source. A blocking
    /// `read` on stdin leaves a thread parked inside Foundation, which has been
    /// observed to stall ScreenCaptureKit's first `SCShareableContent` request.
    /// Commands themselves are delivered on the main queue, where AppKit's
    /// display and privacy APIs expect to run.
    static func start(_ onLine: @escaping (String) -> Void) {
        let source = DispatchSource.makeReadSource(
            fileDescriptor: FileHandle.standardInput.fileDescriptor,
            queue: reads
        )
        self.source = source

        source.setEventHandler {
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let count = read(
                FileHandle.standardInput.fileDescriptor,
                &chunk,
                chunk.count
            )
            guard count > 0 else {
                DispatchQueue.main.async { exit(0) }
                return
            }

            buffer.append(contentsOf: chunk[0..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<newline]
                buffer.removeSubrange(buffer.startIndex...newline)
                guard let line = String(data: lineData, encoding: .utf8),
                      !line.trimmingCharacters(in: .whitespaces).isEmpty
                else { continue }
                DispatchQueue.main.async { onLine(line) }
            }

            if buffer.count > 4 * 1024 * 1024 {
                buffer.removeAll(keepingCapacity: true)
            }
        }
        source.resume()
    }
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8((value >> 24) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8(value & 0xFF))
}

func appendUInt16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8(value & 0xFF))
}
