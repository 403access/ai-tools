import Foundation

/// Written by the hub before the helper starts. Paths are absolute.
struct VMConfig: Codable {
    let id: String
    let name: String
    let cpuCount: Int
    let memoryBytes: UInt64
    let diskPath: String
    let efiVariableStore: String
    let machineIdentifier: String
    let macAddress: String
    let serialLog: String
    let runtimeFile: String
    let pidFile: String

    static func load(path: String) throws -> VMConfig {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(VMConfig.self, from: data)
    }
}

/// Discovered by the hub so it never has to guess a port. The helper listens on
/// loopback only; the hub's Bearer token protects remote access.
struct RuntimeRecord: Codable {
    let pid: Int32
    let version: String
    let controlPort: Int
    let serialPort: Int
    let startedAt: Int64
}

enum FileSupport {
    static let helperVersion = "1.0.0"

    static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }

    static func ensureDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
    }

    static func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
        try ensureDirectory((path as NSString).deletingLastPathComponent)
        let data = try JSONEncoder().encode(value)
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    static func remove(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }
}

enum SocketError: LocalizedError {
    case create(String)
    case bind(String)
    case listen(String)
    case port(String)

    var errorDescription: String? {
        switch self {
        case .create(let detail): return "Could not create a socket: \(detail)"
        case .bind(let detail): return "Could not bind 127.0.0.1: \(detail)"
        case .listen(let detail): return "Could not listen on 127.0.0.1: \(detail)"
        case .port(let detail): return "Could not read the bound port: \(detail)"
        }
    }
}

/// A loopback-only TCP listener. Virtualization's helper runs as the same user
/// as the hub, and the hub is the only client; using TCP avoids macOS's ~104
/// byte limit on Unix-domain socket paths.
final class LoopbackServer {
    private let queue: DispatchQueue
    private let onAccept: (Int32) -> Void
    private var source: DispatchSourceRead?
    private(set) var port: Int = 0

    init(label: String, onAccept: @escaping (Int32) -> Void) {
        self.queue = DispatchQueue(label: label)
        self.onAccept = onAccept
    }

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.create(String(cString: strerror(errno))) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let detail = String(cString: strerror(errno))
            close(fd)
            throw SocketError.bind(detail)
        }
        guard listen(fd, 16) == 0 else {
            let detail = String(cString: strerror(errno))
            close(fd)
            throw SocketError.listen(detail)
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(fd, sockaddrPointer, &length)
            }
        }
        guard named == 0 else {
            let detail = String(cString: strerror(errno))
            close(fd)
            throw SocketError.port(detail)
        }

        port = Int(UInt16(bigEndian: actual.sin_port))
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            var noSigPipe: Int32 = 1
            setsockopt(
                client,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )
            self?.onAccept(client)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}

/// Wraps one accepted file descriptor with a readable DispatchSource and a
/// serialized writer. Reads and writes use the same queue, so responses and
/// console output stay in order.
final class ClientConnection {
    let fd: Int32
    private let queue: DispatchQueue
    /// Mutable so a wrapper can point the callback back at itself after init.
    var onData: (Data) -> Void
    var onClose: () -> Void
    private var source: DispatchSourceRead?
    private var closed = false

    init(
        fd: Int32,
        queue: DispatchQueue,
        onData: @escaping (Data) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.fd = fd
        self.queue = queue
        self.onData = onData
        self.onClose = onClose
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self, !self.closed else { return }
            var buffer = [UInt8](repeating: 0, count: 32 * 1024)
            let count = read(self.fd, &buffer, buffer.count)
            if count > 0 {
                self.onData(Data(buffer[0..<count]))
            } else if count == 0 {
                self.close()
            } else if errno != EAGAIN && errno != EINTR {
                self.close()
            }
        }
        source.setCancelHandler { Darwin.close(self.fd) }
        source.resume()
        self.source = source
    }

    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [weak self] in
            guard let self, !self.closed else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(self.fd, base.advanced(by: offset), raw.count - offset)
                    if written > 0 {
                        offset += written
                    } else if written < 0 && errno == EINTR {
                        continue
                    } else {
                        self.close()
                        return
                    }
                }
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        source?.cancel()
        source = nil
        onClose()
    }
}
