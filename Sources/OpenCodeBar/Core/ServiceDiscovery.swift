import Foundation

struct ServiceLocation: Sendable {
    var url: URL
    var password: String
}

/// Locates the running OpenCode background service.
///
/// The service listens on loopback and is protected by HTTP Basic auth. The
/// password lives in `<config>/opencode/service.json`; the URL is discovered
/// from the CLI or, failing that, from `lsof`.
enum ServiceDiscovery {
    static func home() -> URL { FileManager.default.homeDirectoryForCurrentUser }

    static func configDir() -> URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("opencode", isDirectory: true)
        }
        return home().appendingPathComponent(".config/opencode", isDirectory: true)
    }

    static func dataDir() -> URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("opencode", isDirectory: true)
        }
        return home().appendingPathComponent(".local/share/opencode", isDirectory: true)
    }

    /// Basic-auth password for the local service, if it can be read.
    static func password() -> String? {
        let url = configDir().appendingPathComponent("service.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let password = obj["password"] as? String,
              !password.isEmpty
        else { return nil }
        return password
    }

    static func load() -> ServiceLocation? {
        guard let password = password(), let url = discoverURL() else { return nil }
        return ServiceLocation(url: url, password: password)
    }

    // MARK: - URL discovery

    static func discoverURL() -> URL? {
        if let url = runServiceStatus() { return url }
        if let url = lsofURL() { return url }
        if let url = logURL() { return url }
        return nil
    }

    private static func runServiceStatus() -> URL? {
        let output: String?
        if let binary = opencodeBinary() {
            output = run(binary, ["service", "status"], timeout: 4)
        } else {
            output = run("/bin/zsh", ["-lc", "opencode service status 2>/dev/null"], timeout: 5)
        }
        guard let output, let url = firstURL(in: output) else { return nil }
        return url
    }

    private static func lsofURL() -> URL? {
        guard let output = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-c", "opencode"], timeout: 4)
        else { return nil }
        return firstURL(in: output, requireLoopback: true)
    }

    private static func logURL() -> URL? {
        let log = dataDir().appendingPathComponent("log/opencode.log")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 512 * 1024
        let start = size > window ? size - window : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        return firstURL(in: text, requireLoopback: true)
    }

    private static func opencodeBinary() -> String? {
        let home = home()
        let candidates = [
            home.appendingPathComponent(".opencode/bin/opencode").path,
            "/opt/homebrew/bin/opencode",
            "/usr/local/bin/opencode",
            home.appendingPathComponent(".local/bin/opencode").path,
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = "\(dir)/opencode"
                if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
            }
        }
        if let out = run("/bin/zsh", ["-lc", "command -v opencode"], timeout: 3) {
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) { return trimmed }
        }
        return nil
    }

    // MARK: - Helpers

    private static func firstURL(in text: String, requireLoopback: Bool = false) -> URL? {
        let pattern = "https?://[A-Za-z0-9._-]+:[0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        // Prefer loopback addresses and the last match (most recent).
        var fallback: URL?
        for match in matches.reversed() {
            guard let r = Range(match.range, in: text) else { continue }
            let raw = String(text[r])
            if requireLoopback && !raw.contains("127.0.0.1") && !raw.contains("localhost") { continue }
            let url = URL(string: raw)
            if raw.contains("127.0.0.1") || raw.contains("localhost") { return url }
            if fallback == nil { fallback = url }
        }
        return requireLoopback ? nil : fallback
    }

    /// Runs a process and returns stdout, terminating it if it exceeds `timeout`.
    @discardableResult
    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(15_000)
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
