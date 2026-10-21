import Foundation

/// Shared filesystem locations for OpenCode and OpenCodeBar configuration.
///
/// Kept as a small utility after the app moved to the hub: connection details
/// live next to OpenCode's own config so both have a predictable home.
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
}
