import AppKit

/// AppKit entry point for the menu bar app.
///
/// OpenCodeBar owns its status item directly instead of using a
/// `MenuBarExtra` scene: a left click opens the desktop window while a right
/// click opens the compact panel, and `MenuBarExtra` cannot make that
/// distinction.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Both surfaces share the same state.
        DesktopWindowController.shared.attach(state)
        StatusItemController.shared.attach(state)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        StatusItemController.shared.install()
        DesktopWindowController.shared.applicationDidFinishLaunching()
        state.start()
    }
}

/// Sets up and runs the AppKit application.
@MainActor
enum AppRuntime {
    static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
