import AppKit
import Combine
import SwiftUI

/// Owns the menu bar status item and routes its two click gestures:
///
/// - left click opens (or raises) the desktop window
/// - right click (or control-click) opens the compact panel in a popover
///
/// `MenuBarExtra` always opens its scene on a plain click, so the status item is
/// created by hand to keep the two destinations separate.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private var state: AppState?
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var rightClickMonitor: Any?
    /// Transient popovers close before the click that dismissed them reaches
    /// the status item, so remember the close and avoid reopening immediately.
    private var lastPanelClose = Date.distantPast

    private override init() {
        super.init()
    }

    /// Starts observing the shared state. Call once, after `AppState` exists.
    func attach(_ state: AppState) {
        guard self.state !== state else { return }
        self.state = state

        state.$activeIDs
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        state.$connection
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        if NSApplication.shared.isRunning {
            install()
        }
    }

    /// Creates the status item. Safe to call more than once.
    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        installRightClickMonitor()
        updateStatusItem()
    }

    /// Right clicks are routed with a local event monitor so they never reach
    /// the button's left-click action. `sendAction(on: [.rightMouseUp])` also
    /// works, but keeping the gestures separate makes the intent explicit.
    private func installRightClickMonitor() {
        guard rightClickMonitor == nil else { return }
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.rightMouseDown, .rightMouseUp]
        ) { [weak self] event in
            guard let self,
                  let window = self.statusItem?.button?.window,
                  event.window === window
            else { return event }

            if event.type == .rightMouseDown {
                self.showPanel()
            }
            return nil
        }
    }

    // MARK: - Clicks

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        // The local monitor usually consumes right clicks first; this is the
        // fallback in case a right-mouse event reaches the button action.
        let isRightClick = event.type == .rightMouseUp
            || event.type == .rightMouseDown
            || event.modifierFlags.contains(.control)

        if isRightClick {
            showPanel()
        } else {
            showDesktop()
        }
    }

    /// The tray app: the compact panel normally opened from the menu bar item.
    private func showPanel() {
        guard let state, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }
        if Date().timeIntervalSince(lastPanelClose) < 0.25 {
            return
        }

        if popover.contentViewController == nil {
            popover.contentViewController = NSHostingController(
                rootView: PanelView().environmentObject(state)
            )
            popover.contentSize = NSSize(
                width: PanelView.panelWidth,
                height: PanelView.panelHeight
            )
            popover.behavior = .transient
            popover.animates = true
            popover.delegate = self
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    func popoverDidClose(_ notification: Notification) {
        lastPanelClose = Date()
    }

    /// The desktop app: the full window with the persistent sidebar.
    private func showDesktop() {
        popover.performClose(nil)
        state?.usesDesktopWindow = true
        // Assignment above opens the window; call again so a window that is
        // already open comes to the front (and un-minimises).
        DesktopWindowController.shared.openWindow()
    }

    // MARK: - Label

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let count = state?.activeCount ?? 0

        let image = NSImage(
            systemSymbolName: count > 0 ? "terminal.fill" : "terminal",
            accessibilityDescription: nil
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
        button.title = count > 0 ? " \(count)" : ""
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        button.toolTip = "OpenCodeBar"
        button.setAccessibilityLabel(
            count > 0 ? "\(count) active OpenCode sessions" : "OpenCode"
        )
    }
}
