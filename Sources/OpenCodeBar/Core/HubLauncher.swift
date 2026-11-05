import Foundation

/// Starts the Bun hub from the macOS app.
///
/// The hub is a separate process in `server/`. During development the app is
/// built from the same checkout, so the server folder is found by walking up
/// from the app bundle. An installed copy cannot do that, so Settings also
/// stores a folder the user picks. The launched process is detached from the
/// app and keeps its output in `~/.local/share/opencodebar/hub.log`, which
/// means the hub survives quitting the menu bar app.
enum HubLauncher {
    /// UserDefaults key for the folder chosen in Settings → Server.
    static let directoryDefaultsKey = "OpenCodeBarHubDirectory"

    enum LaunchError: LocalizedError {
        case serverNotFound
        case bunNotFound
        case logUnavailable(String)
        case launchFailed(String)

        var errorDescription: String? {
            switch self {
            case .serverNotFound:
                return "Could not find the hub server folder. Choose the ai-tools checkout in Settings → Server."
            case .bunNotFound:
                return "Bun is not installed or was not found. Install it from https://bun.sh, then try again."
            case .logUnavailable(let message):
                return "Could not open the hub log: \(message)"
            case .launchFailed(let message):
                return "Could not start the hub: \(message)"
            }
        }
    }

    /// Folder that holds the server's `src/index.ts` and `package.json`.
    static func serverDirectory() -> URL? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        var candidates: [URL] = []

        if let override = environment["OPENCODEBAR_HUB_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            candidates.append(contentsOf: ancestors(of: URL(fileURLWithPath: override, isDirectory: true)))
        }

        if let saved = UserDefaults.standard.string(forKey: directoryDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            candidates.append(contentsOf: ancestors(of: URL(fileURLWithPath: saved, isDirectory: true)))
        }

        // A packaged build can ship the server next to the executable.
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("server", isDirectory: true))
        }

        candidates.append(contentsOf: ancestors(of: Bundle.main.bundleURL))
        candidates.append(contentsOf: ancestors(of: URL(fileURLWithPath: CommandLine.arguments[0])))
        candidates.append(contentsOf: ancestors(of: URL(fileURLWithPath: fileManager.currentDirectoryPath)))

        return findServer(in: candidates)
    }

    /// Returns the first candidate that looks like the hub server. Exposed for
    /// tests; production callers use `serverDirectory()`.
    static func findServer(in candidates: [URL]) -> URL? {
        var seen: Set<String> = []
        for candidate in candidates {
            // Accept either the server folder itself or the checkout that
            // contains it, so the folder picker can point at the repository.
            let options = [
                candidate,
                candidate.appendingPathComponent("server", isDirectory: true),
            ]
            for option in options {
                let path = option.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                if isServerDirectory(option) {
                    return option.standardizedFileURL
                }
            }
        }
        return nil
    }

    /// Location of the hub's stdout/stderr log.
    static var logFileURL: URL {
        dataDirectory().appendingPathComponent("hub.log")
    }

    static func dataDirectory() -> URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true)
                .appendingPathComponent("opencodebar", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencodebar", isDirectory: true)
    }

    /// Whether the hub described by the generated config is already answering.
    static func configuredHubIsRunning() async -> Bool {
        guard let location = HubDiscovery.load() else { return false }
        return await HubAPI.ping(baseURL: location.url)
    }

    /// Starts `bun run src/index.ts` in the server folder and returns its PID.
    static func startServer() async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    guard let directory = serverDirectory() else {
                        throw LaunchError.serverNotFound
                    }
                    guard let bun = bunExecutable() else {
                        throw LaunchError.bunNotFound
                    }

                    let log = try openLog()
                    let started = ISO8601DateFormatter().string(from: Date())
                    try log.write(contentsOf: Data(
                        "\n[OpenCodeBar] Starting hub in \(directory.path) at \(started)\n".utf8
                    ))

                    let process = Process()
                    process.executableURL = bun
                    process.arguments = ["run", "src/index.ts"]
                    process.currentDirectoryURL = directory
                    process.environment = environment(for: bun)
                    process.standardInput = FileHandle.nullDevice
                    process.standardOutput = log
                    process.standardError = log
                    try process.run()

                    // Keep the descriptor open for the child's lifetime. The
                    // Process object itself can go away; the child is not
                    // terminated when its parent exits.
                    logHandle = log
                    continuation.resume(returning: process.processIdentifier)
                } catch let error as LaunchError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: LaunchError.launchFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Discovery

    private static func ancestors(of url: URL) -> [URL] {
        var result: [URL] = []
        var current = url.standardizedFileURL
        if !current.hasDirectoryPath {
            current.deleteLastPathComponent()
        }
        for _ in 0..<8 {
            result.append(current.appendingPathComponent("server", isDirectory: true))
            result.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return result
    }

    private static func isServerDirectory(_ url: URL) -> Bool {
        let fileManager = FileManager.default
        let index = url.appendingPathComponent("src/index.ts")
        guard fileManager.fileExists(atPath: index.path) else { return false }

        let package = url.appendingPathComponent("package.json")
        guard let data = try? Data(contentsOf: package),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // The index file is enough when package.json is unreadable.
            return true
        }
        return object["name"] as? String == "opencodebar-hub"
    }

    /// Finds Bun in the environment, the usual install locations, then the
    /// user's login shell so Homebrew and bun's own installer are both found
    /// when the app is launched from Finder.
    private static func bunExecutable() -> URL? {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        var candidates: [String] = []
        if let override = environment["OPENCODEBAR_BUN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            candidates.append(override)
        }

        candidates.append(contentsOf: [
            "/opt/homebrew/bin/bun",
            "/usr/local/bin/bun",
            "/opt/local/bin/bun",
            "/usr/bin/bun",
        ])
        candidates.append(
            fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".bun/bin/bun").path
        )

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                candidates.append("\(directory)/bun")
            }
        }

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return loginShellLookup("bun")
    }

    private static func loginShellLookup(_ command: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v \(command)"]
        process.standardError = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + 4) == .timedOut {
            process.terminate()
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func environment(for bun: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let bunDirectory = bun.deletingLastPathComponent().path
        let path = environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if !path.split(separator: ":").map(String.init).contains(bunDirectory) {
            environment["PATH"] = "\(bunDirectory):\(path)"
        }
        return environment
    }

    // MARK: - Logging

    private static var logHandle: FileHandle?

    private static func openLog() throws -> FileHandle {
        let fileManager = FileManager.default
        let directory = logFileURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(
                    atPath: logFileURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            let handle = try FileHandle(forWritingTo: logFileURL)
            try handle.seekToEnd()
            return handle
        } catch {
            throw LaunchError.logUnavailable(error.localizedDescription)
        }
    }
}
