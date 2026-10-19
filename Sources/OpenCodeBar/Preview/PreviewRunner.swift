import AppKit
import SwiftUI

/// Development helper used by the docs/build workflow.
///
/// - `--preview`                 renders the panel in a normal window
/// - `--preview --tab usage`     opens a specific tab
/// - `--screenshot <path>`       renders the panel offscreen to a PNG and exits
/// - `--screenshot <path> --scale 2 --tab usage`
enum PreviewRunner {
    @MainActor
    static func run() {
        let arguments = CommandLine.arguments
        if let path = value(after: "--screenshot", in: arguments) {
            let scale = CGFloat(Double(value(after: "--scale", in: arguments) ?? "2") ?? 2)
            capture(to: path, scale: scale)
        } else {
            showWindow()
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    // MARK: - Interactive preview window

    @MainActor
    private static func showWindow() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let state = AppState()
        state.start()

        // `--detail` opens the first running (or most recent) session once the
        // service data has loaded.
        if CommandLine.arguments.contains("--detail") {
            Task { @MainActor in
                for _ in 0..<50 {
                    if let session = state.runningSessions.first ?? state.sessions.first {
                        state.selectedSession = session
                        return
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

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

    // MARK: - Offscreen screenshot

    @MainActor
    private static func capture(to path: String, scale: CGFloat) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        // Keep the rendered panel consistent with the app's appearance.
        app.appearance = NSAppearance(named: .darkAqua)

        let state = AppState()
        state.start()

        // Pump the run loop so the async fetches and event stream can populate.
        let deadline = Date().addingTimeInterval(7)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        // `--detail` opens the first running session (or most recent one), which
        // makes it easy to iterate on the conversation view.
        if CommandLine.arguments.contains("--detail") {
            state.selectedSession = state.runningSessions.first ?? state.sessions.first
        }

        let hosting = NSHostingView(rootView: ScreenshotRoot(state: state))
        hosting.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 700),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = ScreenshotRoot.background
        window.contentView = hosting
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()

        // Give the detail view a moment to fetch its conversation.
        if CommandLine.arguments.contains("--detail") {
            let detailDeadline = Date().addingTimeInterval(3)
            while Date() < detailDeadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            hosting.layoutSubtreeIfNeeded()
        }

        var size = hosting.fittingSize
        if size.height < 50 || size.width < 50 {
            size = NSSize(width: 400, height: 640)
        }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        window.setContentSize(size)

        let pixelsWide = Int((size.width * scale).rounded())
        let pixelsHigh = Int((size.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            FileHandle.standardError.write(Data("failed to create bitmap\n".utf8))
            exit(1)
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to encode png\n".utf8))
            exit(1)
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write(Data("failed to write \(path): \(error)\n".utf8))
            exit(1)
        }
        print("Wrote \(path) (\(pixelsWide)x\(pixelsHigh))")
        exit(0)
    }
}

/// Renders the panel on a solid dark background, mimicking the material the
/// menu bar window normally provides.
private struct ScreenshotRoot: View {
    @ObservedObject var state: AppState

    static let background = NSColor(calibratedRed: 0.135, green: 0.137, blue: 0.147, alpha: 1)

    var body: some View {
        ZStack {
            Color(nsColor: Self.background)
            PanelView().environmentObject(state)
        }
    }
}
