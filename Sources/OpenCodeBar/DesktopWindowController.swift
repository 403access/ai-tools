import AppKit
import Combine
import SwiftUI

/// Manages the optional full desktop window.
///
/// The menu bar status item is always present (see `StatusItemController`).
/// Turning on the desktop window switches the activation policy to `.regular`
/// (Dock icon and app menu) and shows a resizable window that shares the same
/// `AppState` as the panel. Closing the window goes back to an accessory app,
/// so the status item keeps working on its own.
@MainActor
final class DesktopWindowController: NSObject, NSWindowDelegate {
    static let shared = DesktopWindowController()

    private weak var state: AppState?
    private var window: NSWindow?
    private var preference: AnyCancellable?
    /// Set while the controller is reacting to the user closing the window, so
    /// clearing the preference does not try to close it a second time.
    private var isClosing = false
    /// AppKit closes windows while the app terminates. Keep the saved desktop
    /// preference in that case so the window comes back on the next launch.
    private var isTerminating = false

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    /// Starts following the app's desktop-window preference. Call once, after
    /// the shared `AppState` exists.
    func attach(_ state: AppState) {
        guard self.state !== state else { return }
        self.state = state

        preference = state.$usesDesktopWindow
            .dropFirst()
            .sink { [weak self] _ in
                self?.applyPreference()
            }

        // The launch notification is normally still ahead of us; if the app is
        // already running (a second attach, for example), apply right away.
        if NSApplication.shared.isRunning {
            applyPreference()
        }
    }

    /// Called from the app delegate once AppKit has finished launching.
    func applicationDidFinishLaunching() {
        // A main menu lets standard editing shortcuts work in the panel's text
        // fields even before the desktop window exists.
        installMainMenu()

        // `--desktop` turns desktop mode on for this launch; `make desktop`
        // uses it. The preference is remembered, like the Settings toggle.
        if CommandLine.arguments.contains("--desktop") {
            state?.usesDesktopWindow = true
        } else {
            applyPreference()
        }
    }

    func applyPreference() {
        guard let state else { return }
        if state.usesDesktopWindow {
            openWindow()
        } else {
            closeWindow()
        }
    }

    func openWindow() {
        guard let state else { return }
        if window == nil {
            window = makeWindow(state: state)
        }
        NSApp.setActivationPolicy(.regular)
        installMainMenu()
        window?.deminiaturize(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        guard !isClosing, let window else {
            NSApp.setActivationPolicy(.accessory)
            return
        }
        window.close()
    }

    // MARK: - Window

    private func makeWindow(state: AppState) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OpenCodeBar"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 520)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: DesktopView().environmentObject(state)
        )
        window.center()
        // Remember the user's size and position across launches.
        window.setFrameAutosaveName("OpenCodeBarDesktopWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        isClosing = true
        // Keep the saved preference in step with reality: closing the window
        // returns the app to menu-bar-only mode (and removes the Dock icon).
        // Quitting the app is different — the window should come back next
        // time.
        if !isTerminating {
            state?.usesDesktopWindow = false
        }
        isClosing = false
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func applicationWillTerminate() {
        isTerminating = true
    }

    // MARK: - Main menu

    /// The app is normally an accessory with no visible main menu. A main menu
    /// still routes standard editing shortcuts (copy, paste, undo) to the
    /// panel's text fields, and it is what a regular desktop app shows in the
    /// menu bar. It replaces any placeholder menu SwiftUI created.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About OpenCodeBar",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide OpenCodeBar",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        let hideOthers = appMenu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(
            withTitle: "Show All",
            action: #selector(NSApplication.unhideAllApplications(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit OpenCodeBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let refresh = viewMenu.addItem(
            withTitle: "Refresh",
            action: #selector(refreshNow(_:)),
            keyEquivalent: "r"
        )
        refresh.target = self

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc private func refreshNow(_ sender: Any?) {
        guard let state else { return }
        Task { await state.refreshAll() }
    }
}
