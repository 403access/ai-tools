import AppKit
import SwiftUI

/// Development helper used by the docs/build workflow.
///
/// - `--preview`                 renders the panel in a normal window
/// - `--preview --tab usage`     opens a specific tab
/// - `--screenshot <path>`       renders the panel offscreen to a PNG and exits
/// - `--screenshot <path> --scale 2 --tab usage`
/// - `--memory`                  renders the memory monitor instead of the panel
/// - `--memory --system-fixture <path>` feeds it a captured `/api/system` JSON
/// - `--memory-process <pid>` / `--memory-group <name>` render a process or app
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

        // `--session <id>` opens a specific session (useful for previews and
        // screenshots of sessions with subagents).
        if let id = value(after: "--session", in: CommandLine.arguments) {
            Task { @MainActor in
                for _ in 0..<50 {
                    if let session = state.sessions.first(where: { $0.id == id }) {
                        state.open(session)
                        return
                    }
                    if let fetched = await state.fetchSession(id: id) {
                        state.open(fetched)
                        return
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        // `--project-detail` opens the first project's detail page.
        if CommandLine.arguments.contains("--project-detail") {
            Task { @MainActor in
                for _ in 0..<50 {
                    if let project = state.orderedProjects.first {
                        state.open(project)
                        return
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }

        // `--files <path>` opens the host file browser at that folder.
        if let path = value(after: "--files", in: CommandLine.arguments) {
            state.openFileBrowser(at: path)
        }

        // `--device-detail` opens the first connected device from Settings.
        if CommandLine.arguments.contains("--device-detail") {
            Task { @MainActor in
                await state.refreshSettings(force: true)
                if let device = state.devices.first(where: \.connected) ?? state.devices.first {
                    state.open(device)
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

        // `--system-fixture <path>` loads a previously captured `/api/system`
        // envelope. Useful for iterating on the memory monitor when a live hub
        // is slow to collect its static inventory.
        if let fixture = value(after: "--system-fixture", in: CommandLine.arguments) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: fixture))
                let envelope = try JSONDecoder().decode(SystemInfoEnvelope.self, from: data)
                state.systemInfo = envelope.data
                state.systemInfoFetchedAt = Date()
            } catch {
                FileHandle.standardError.write(Data("system fixture failed: \(error)\n".utf8))
            }
        }

        // Pump the run loop so the async fetches and event stream can populate.
        // Slow tabs (the first System fetch scans apps and Homebrew) can ask for
        // a longer settle window with `--wait <seconds>`.
        let wait = Double(value(after: "--wait", in: CommandLine.arguments) ?? "7") ?? 7
        let deadline = Date().addingTimeInterval(max(1, wait))
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        // `--detail` opens the first running session (or most recent one), which
        // makes it easy to iterate on the conversation view.
        if CommandLine.arguments.contains("--detail") {
            state.selectedSession = state.runningSessions.first ?? state.sessions.first
        }

        // `--session <id>` opens a specific session. If it is not in the recent
        // list, it is looked up directly.
        if let id = value(after: "--session", in: CommandLine.arguments) {
            if let session = state.sessions.first(where: { $0.id == id }) {
                state.open(session)
            } else {
                var fetched: Session?
                Task { @MainActor in fetched = await state.fetchSession(id: id) }
                let deadline = Date().addingTimeInterval(3)
                while fetched == nil && Date() < deadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                }
                if let fetched { state.open(fetched) }
            }
        }

        // `--project-detail` opens the first project's detail page, for the
        // same reason.
        let wantsProjectDetail = CommandLine.arguments.contains("--project-detail")
        if wantsProjectDetail, let project = state.orderedProjects.first {
            state.open(project)
        }

        // `--files <path>` opens the host file browser for screenshots.
        let wantsFiles = value(after: "--files", in: CommandLine.arguments) != nil
        if let path = value(after: "--files", in: CommandLine.arguments) {
            state.openFileBrowser(at: path)
        }

        // Settings fetches its server/device data when the view appears, which
        // happens after the run loop above has already settled.
        let wantsSettings = value(after: "--tab", in: CommandLine.arguments)?.lowercased() == "settings"

        // `--terminal` renders the first terminal instead of the panel, for
        // inspecting the emulator without driving the UI by hand.
        let wantsTerminal = CommandLine.arguments.contains("--terminal")
        if wantsTerminal {
            var finished = false
            Task { @MainActor in
                await state.refreshTerminals(force: true)
                finished = true
            }
            let deadline = Date().addingTimeInterval(10)
            while !finished && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }

        // `--host-terminal` renders the first Terminal.app tab instead.
        let wantsHostTerminal = CommandLine.arguments.contains("--host-terminal")
        if wantsHostTerminal {
            var finished = false
            Task { @MainActor in
                await state.refreshHostTerminals(force: true)
                finished = true
            }
            let deadline = Date().addingTimeInterval(10)
            while !finished && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }

        // `--memory` renders the memory monitor directly, for iterating on the
        // breakdown and process list without opening the panel by hand.
        let wantsMemory = CommandLine.arguments.contains("--memory")

        // The offscreen harness never runs SwiftUI's `.task`, so preload the
        // System tab explicitly. Its first fetch scans apps and Homebrew. A
        // fixture already provides the snapshot, so skip the live fetch.
        let hasFixture = value(after: "--system-fixture", in: CommandLine.arguments) != nil
        if !hasFixture && (value(after: "--tab", in: CommandLine.arguments)?.lowercased() == "system" || wantsMemory) {
            var finished = false
            Task { @MainActor in
                await state.refreshSystemInfo(force: true)
                await state.refreshTerminals(force: true)
                finished = true
            }
            let deadline = Date().addingTimeInterval(25)
            while !finished && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }

        // `--device-detail` opens a device page, which also needs the Settings
        // payload before the first device exists.
        let wantsDeviceDetail = CommandLine.arguments.contains("--device-detail")
        if wantsDeviceDetail {
            var finished = false
            Task { @MainActor in
                await state.refreshSettings(force: true)
                finished = true
            }
            let deadline = Date().addingTimeInterval(3)
            while !finished && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
            if let device = state.devices.first(where: \.connected) ?? state.devices.first {
                state.open(device)
            }
        }

        // `--memory-process <pid>` and `--memory-group <name>` render the
        // drill-in pages so they can be inspected without clicking through.
        let memoryPID = value(after: "--memory-process", in: CommandLine.arguments).flatMap(Int.init)
        let memoryGroupName = value(after: "--memory-group", in: CommandLine.arguments)

        let root: AnyView
        if wantsMemory,
           let memoryPID,
           let process = state.systemInfo?.processes.all.first(where: { $0.pid == memoryPID }) {
            root = AnyView(
                MemoryProcessDetailView(process: process)
                    .environmentObject(state)
            )
        } else if wantsMemory,
                  let memoryGroupName,
                  let info = state.systemInfo,
                  let group = SystemProcessGrouping.groups(for: info)
                    .first(where: { $0.name.localizedCaseInsensitiveCompare(memoryGroupName) == .orderedSame }) {
            root = AnyView(
                MemoryProcessGroupDetailView(group: group)
                    .environmentObject(state)
            )
        } else if wantsMemory {
            root = AnyView(
                MemoryMonitorView()
                    .environmentObject(state)
            )
        } else if wantsTerminal,
                  let terminal = state.terminals.first,
                  let api = state.api {
            root = AnyView(
                TerminalDetailView(terminal: terminal, api: api)
                    .environmentObject(state)
            )
        } else if wantsHostTerminal,
                  let terminal = state.hostTerminals.first,
                  let api = state.api {
            root = AnyView(
                HostTerminalDetailView(terminal: terminal, api: api)
                    .environmentObject(state)
            )
        } else {
            root = AnyView(ScreenshotRoot(state: state))
        }

        let hosting = NSHostingView(rootView: root)
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

        // Give the detail view a moment to fetch its conversation or scoped
        // project analytics.
        if CommandLine.arguments.contains("--detail")
            || CommandLine.arguments.contains("--session")
            || wantsProjectDetail
            || wantsDeviceDetail
            || wantsSettings
            || wantsFiles
            || wantsTerminal
            || wantsHostTerminal
            || wantsMemory {
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
