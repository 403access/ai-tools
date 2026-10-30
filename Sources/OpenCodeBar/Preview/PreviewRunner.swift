import AppKit
import SwiftUI

/// Development helper used by the docs/build workflow.
///
/// - `--preview`                 renders the panel in a normal window
/// - `--preview --tab usage`     opens a specific tab
/// - `--usage-mode activity`     opens a page of the Usage tab
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

    /// Maps `--project-mode flows` (or any ProjectDetailMode title) to a tab.
    private static func projectMode(
        from arguments: [String]
    ) -> AppState.ProjectDetailMode? {
        guard let raw = value(after: "--project-mode", in: arguments) else { return nil }
        return AppState.ProjectDetailMode.allCases.first {
            $0.rawValue.localizedCaseInsensitiveCompare(raw) == .orderedSame
        }
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
            if let requested = projectMode(from: CommandLine.arguments) {
                state.projectMode = requested
            }
            let requestedProject = value(after: "--project", in: CommandLine.arguments)
            Task { @MainActor in
                for _ in 0..<50 {
                    if let project = requestedProject.flatMap({ requested in
                        state.orderedProjects.first {
                            $0.id == requested || $0.canonical == requested
                        }
                    }) ?? state.orderedProjects.first {
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

        // `--deployment-detail` opens the first iPhone/iPad with deployments.
        if CommandLine.arguments.contains("--deployment-detail") {
            Task { @MainActor in
                for _ in 0..<50 {
                    await state.refreshDeployments(force: true)
                    if let device = state.deploymentDevices.first {
                        state.open(device)
                        return
                    }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
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
        // same reason. `--project` selects one by id or path, and
        // `--project-mode` chooses the tab that should be visible.
        let wantsProjectDetail = CommandLine.arguments.contains("--project-detail")
        let requestedProjectMode = projectMode(from: CommandLine.arguments)
        if let requestedProjectMode {
            state.projectMode = requestedProjectMode
        }
        if wantsProjectDetail {
            let requestedProject = value(after: "--project", in: CommandLine.arguments)
            let project = requestedProject.flatMap { requested in
                state.orderedProjects.first {
                    $0.id == requested || $0.canonical == requested
                }
            } ?? state.orderedProjects.first
            if let project {
                state.open(project)
                if requestedProjectMode == .flows {
                    var finished = false
                    Task { @MainActor in
                        await state.loadProjectFlows(project.id, force: true)
                        finished = true
                    }
                    let deadline = Date().addingTimeInterval(20)
                    while !finished && Date() < deadline {
                        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    }
                }
            }
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

        // `--deployment-detail` needs the deployment payload before the device
        // can be selected, so preload it like the device page does.
        let wantsDeploymentDetail = CommandLine.arguments.contains("--deployment-detail")
        if wantsDeploymentDetail {
            for _ in 0..<10 {
                var finished = false
                Task { @MainActor in
                    await state.refreshDeployments(force: true)
                    finished = true
                }
                let deadline = Date().addingTimeInterval(3)
                while !finished && Date() < deadline {
                    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                }
                if !state.deploymentDevices.isEmpty { break }
            }
            if let device = state.deploymentDevices.first {
                state.open(device)
            }
        }

        // `--settings-deployments` renders the Settings → Deployments section
        // alone, since it sits below the fold of the Settings scroll view.
        let wantsDeploymentsSection = CommandLine.arguments.contains("--settings-deployments")
        if wantsDeploymentsSection {
            var finished = false
            Task { @MainActor in
                await state.refreshDeployments(force: true)
                finished = true
            }
            let deadline = Date().addingTimeInterval(5)
            while !finished && Date() < deadline {
                RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }

        // `--memory-process <pid>` and `--memory-group <name>` render the
        // drill-in pages so they can be inspected without clicking through.
        let memoryPID = value(after: "--memory-process", in: CommandLine.arguments).flatMap(Int.init)
        let memoryGroupName = value(after: "--memory-group", in: CommandLine.arguments)

        let root: AnyView
        if wantsDeploymentsSection {
            root = AnyView(
                ScrollView {
                    SettingsDeploymentsSection()
                        .environmentObject(state)
                        .padding(12)
                }
                .frame(width: 400)
                .background(Color(nsColor: ScreenshotRoot.background))
            )
        } else if wantsMemory,
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
            || wantsDeploymentDetail
            || wantsDeploymentsSection
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
