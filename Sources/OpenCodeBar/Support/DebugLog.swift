import Foundation

/// Tiny opt-in logger for development. Enabled with
/// `OPENCODEBAR_DEBUG_SUBAGENTS=1`; writes to stderr so it is visible even when
/// stdout is redirected (as in the preview and screenshot harnesses).
enum DebugLog {
    static var subagentsEnabled: Bool {
        ProcessInfo.processInfo.environment["OPENCODEBAR_DEBUG_SUBAGENTS"] != nil
    }

    static func subagents(_ message: @autoclosure () -> String) {
        guard subagentsEnabled else { return }
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}
