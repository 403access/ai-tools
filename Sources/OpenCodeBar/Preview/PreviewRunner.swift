import AppKit
import SwiftUI

/// Renders the panel in a regular window so the UI can be inspected and
/// screenshotted without opening the menu bar popover.
enum PreviewRunner {
    @MainActor
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let state = AppState()
        state.start()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenCodeBar"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PanelView().environmentObject(state))
        window.center()
        window.makeKeyAndOrderFront(nil)

        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
