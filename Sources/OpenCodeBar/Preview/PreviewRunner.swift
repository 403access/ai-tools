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
        #if DEBUG
        if let folder = value(after: "--sheet-gallery", in: arguments) {
            let scale = CGFloat(Double(value(after: "--scale", in: arguments) ?? "2") ?? 2)
            renderSheetGallery(to: folder, scale: scale)
            return
        }
        #endif
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
        if CommandLine.arguments.contains("--command-bar") {
            state.isCommandBarPresented = true
        }
        if CommandLine.arguments.contains("--usage") {
            state.tab = .usage
        }

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

    #if DEBUG
    // MARK: - Sheet gallery

    /// Renders every meaningful state of the New Session and Retry sheets into
    /// `retry/` and `new-session/` folders. Used to review the visual states
    /// without clicking through the app.
    @MainActor
    private static func renderSheetGallery(to folder: String, scale: CGFloat) {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .darkAqua)

        let state = AppState()
        let fixtures = SheetGalleryFixtures()
        state.projects = [fixtures.project.id: fixtures.project]
        state.orderedProjects = [fixtures.project]

        let root = URL(fileURLWithPath: folder, isDirectory: true)
        let retryDir = root.appendingPathComponent("retry", isDirectory: true)
        let newSessionDir = root.appendingPathComponent("new-session", isDirectory: true)
        // The gallery is generated; remove the previous renders so renamed
        // scenarios do not leave stale images behind.
        try? FileManager.default.removeItem(at: retryDir)
        try? FileManager.default.removeItem(at: newSessionDir)
        for directory in [root, retryDir, newSessionDir] {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var retryRows: [(String, String)] = []
        var newSessionRows: [(String, String)] = []

        func renderRetry(
            _ name: String,
            _ description: String,
            preview: RetryTurnSheet.PreviewState,
            failure: FailedTurn? = nil
        ) {
            let view = RetryTurnSheet(
                session: fixtures.session,
                failure: failure ?? fixtures.failure,
                onForked: { _ in },
                preview: preview
            )
            .environmentObject(state)
            renderSheet(AnyView(view), to: retryDir.appendingPathComponent(name), scale: scale)
            retryRows.append((name, description))
        }

        func renderNewSession(
            _ name: String,
            _ description: String,
            preview: NewSessionSheet.PreviewState
        ) {
            let view = NewSessionSheet(preview: preview).environmentObject(state)
            renderSheet(AnyView(view), to: newSessionDir.appendingPathComponent(name), scale: scale)
            newSessionRows.append((name, description))
        }

        // Retry: same session with the failed turn's settings.
        var retryDefault = RetryTurnSheet.PreviewState()
        retryDefault.models = fixtures.models
        retryDefault.agents = fixtures.agents
        retryDefault.modelChoice = fixtures.selectedChoice
        retryDefault.selectedVariant = "high"
        retryDefault.selectedAgent = "build"
        renderRetry(
            "01-same-session.png",
            "Retry in this session with the failed prompt and the turn's original model/agent.",
            preview: retryDefault
        )

        // Retry: a different model, variant and agent.
        var retrySettings = retryDefault
        retrySettings.modelChoice = fixtures.alternateChoice
        retrySettings.selectedVariant = "high"
        retrySettings.selectedAgent = "plan"
        renderRetry(
            "02-model-variant-agent.png",
            "Retry with a different model, the high variant and the plan agent.",
            preview: retrySettings
        )

        // Retry: fork destination.
        var retryFork = retrySettings
        retryFork.destination = .newSession
        renderRetry(
            "03-new-fork.png",
            "Fork the conversation before the failed prompt and retry in a new session.",
            preview: retryFork
        )

        // Retry: provider error card.
        renderRetry(
            "04-provider-error.png",
            "The failed turn's provider error is shown above the retry settings.",
            preview: retryDefault,
            failure: fixtures.failureWithError
        )

        // Retry: catalogs loading.
        var retryLoading = RetryTurnSheet.PreviewState()
        retryLoading.isLoading = true
        renderRetry(
            "05-loading-catalogs.png",
            "The sheet before the model and agent catalogs have loaded.",
            preview: retryLoading
        )

        // Retry: catalog load failure.
        var retryCatalogError = RetryTurnSheet.PreviewState()
        retryCatalogError.loadError = "Couldn’t load models: OpenCode is offline."
        renderRetry(
            "06-catalog-error.png",
            "The model/agent catalogs could not be loaded.",
            preview: retryCatalogError
        )

        // Retry: submit failure.
        var retrySubmitError = retrySettings
        retrySubmitError.errorMessage = "This Go model trains on request data. Choose a model whose policy you accept."
        renderRetry(
            "07-submit-error.png",
            "A retry submission failed and the error is shown below the settings.",
            preview: retrySubmitError
        )

        // Retry: working/disabled.
        var retryWorking = retrySettings
        retryWorking.isWorking = true
        renderRetry(
            "08-working.png",
            "The sheet while the retry is being submitted.",
            preview: retryWorking
        )

        // Retry: long prompt and long error.
        var retryLong = retrySettings
        retryLong.prompt = fixtures.longPrompt
        retryLong.errorMessage = fixtures.longError
        renderRetry(
            "09-long-content.png",
            "A long prompt and error message stress the sheet's wrapping and height.",
            preview: retryLong,
            failure: fixtures.failureWithError
        )

        // Retry: the "continue" shortcut.
        var retryContinue = retrySettings
        retryContinue.prompt = "continue"
        renderRetry(
            "10-send-continue.png",
            "The Send “continue” shortcut fills the prompt for an interrupted turn.",
            preview: retryContinue
        )

        // Retry: the model browser it opens.
        let retryPicker = ModelPickerSheet(
            models: fixtures.models,
            selection: fixtures.selectedChoice,
            variant: "high"
        ) { _, _ in }
        renderSheet(
            AnyView(retryPicker),
            to: retryDir.appendingPathComponent("11-model-picker.png"),
            scale: scale
        )
        retryRows.append(("11-model-picker.png", "The searchable model browser opened from Retry."))

        // New Session: existing folder, default settings.
        var newDefault = NewSessionSheet.PreviewState()
        newDefault.directory = fixtures.project.canonical
        newDefault.models = fixtures.models
        newDefault.agents = fixtures.agents
        renderNewSession(
            "01-existing-default.png",
            "Create a session in an existing project with OpenCode's default model and agent.",
            preview: newDefault
        )

        // New Session: chosen model, variant and agent.
        var newSettings = newDefault
        newSettings.title = "Match iPhone dark theme"
        newSettings.prompt = fixtures.prompt
        newSettings.modelChoice = fixtures.selectedChoice
        newSettings.selectedVariant = "high"
        newSettings.selectedAgent = "build"
        renderNewSession(
            "02-model-variant-agent.png",
            "Create a session with a chosen model, high variant, build agent, title and first message.",
            preview: newSettings
        )

        // New Session: clone a repository.
        var newClone = newDefault
        newClone.source = "clone"
        newClone.repositoryURL = "github.com/403access/ai-tools"
        newClone.parentDirectory = "~/Developer"
        newClone.folderName = ""
        newClone.prompt = fixtures.prompt
        renderNewSession(
            "03-clone-repository.png",
            "Clone a Git repository on the Mac, then create the session in it.",
            preview: newClone
        )

        // New Session: Git worktree.
        var newWorktree = newSettings
        newWorktree.workspace = "worktree"
        renderNewSession(
            "04-git-worktree.png",
            "Create an isolated Git worktree so the session's changes stay out of the main checkout.",
            preview: newWorktree
        )

        // New Session: scheduled start.
        var newScheduled = newSettings
        newScheduled.startMode = "custom"
        newScheduled.customStart = Date().addingTimeInterval(60 * 60)
        renderNewSession(
            "05-scheduled-start.png",
            "Queue the first message for a later start time.",
            preview: newScheduled
        )

        // New Session: session already created.
        var newCreated = newSettings
        newCreated.createdSession = fixtures.session
        renderNewSession(
            "06-created-session.png",
            "The session exists; the user can fix the first message and retry.",
            preview: newCreated
        )

        // New Session: submit failure.
        var newError = newSettings
        newError.errorMessage = "This Go model trains on request data. Choose a model whose policy you accept."
        renderNewSession(
            "07-send-error.png",
            "Session creation or the first prompt failed.",
            preview: newError
        )

        // New Session: catalogs loading.
        var newLoading = NewSessionSheet.PreviewState()
        newLoading.directory = fixtures.project.canonical
        newLoading.catalogsLoading = true
        renderNewSession(
            "08-loading-catalogs.png",
            "The model and agent section while the catalogs load.",
            preview: newLoading
        )

        // New Session: catalog error.
        var newCatalogError = newDefault
        newCatalogError.catalogError = "Couldn’t load models and agents: OpenCode is offline."
        renderNewSession(
            "09-catalog-error.png",
            "The catalogs could not be loaded for the selected directory.",
            preview: newCatalogError
        )

        // New Session: working/disabled.
        var newWorking = newSettings
        newWorking.isWorking = true
        renderNewSession(
            "10-working.png",
            "The sheet while the session is being created.",
            preview: newWorking
        )

        // New Session: the same model browser.
        renderSheet(
            AnyView(
                ModelPickerSheet(
                    models: fixtures.models,
                    selection: fixtures.selectedChoice,
                    variant: "high"
                ) { _, _ in }
            ),
            to: newSessionDir.appendingPathComponent("11-model-picker.png"),
            scale: scale
        )
        newSessionRows.append(("11-model-picker.png", "The searchable model browser opened from New Session."))

        writeSheetGalleryReadme(
            to: root.appendingPathComponent("README.md"),
            retryRows: retryRows,
            newSessionRows: newSessionRows
        )
        print("Wrote sheet gallery to \(root.path)")
        exit(0)
    }

    @MainActor
    private static func renderSheet(_ view: AnyView, to url: URL, scale: CGFloat) {
        let root = AnyView(
            ZStack {
                Color(nsColor: ScreenshotRoot.background)
                view
            }
            .padding(24)
            .background(Color(nsColor: ScreenshotRoot.background))
        )

        let hosting = NSHostingView(rootView: root)
        hosting.appearance = NSAppearance(named: .darkAqua)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
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

        // Let focus rings and text layout settle before measuring.
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.12))
        hosting.layoutSubtreeIfNeeded()

        var size = hosting.fittingSize
        if size.width < 50 || size.height < 50 {
            size = NSSize(width: 520, height: 700)
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
            FileHandle.standardError.write(Data("failed to create sheet bitmap\n".utf8))
            return
        }
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to encode sheet png\n".utf8))
            return
        }
        do {
            try png.write(to: url)
            print("Wrote \(url.path) (\(pixelsWide)x\(pixelsHigh))")
        } catch {
            FileHandle.standardError.write(Data("failed to write \(url.path): \(error)\n".utf8))
        }
    }

    private static func writeSheetGalleryReadme(
        to url: URL,
        retryRows: [(String, String)],
        newSessionRows: [(String, String)]
    ) {
        func table(_ rows: [(String, String)]) -> String {
            rows.map { "| `\($0.0)` | \($0.1) |" }.joined(separator: "\n")
        }
        let text = """
        # Session sheet gallery

        Offscreen renders of the macOS New Session and Retry sheets. Regenerate with:

        ```sh
        swift build
        .build/debug/OpenCodeBar --sheet-gallery docs/screenshots/session-sheets --scale 2
        ```

        ## Retry

        | Image | Scenario |
        | --- | --- |
        \(table(retryRows))

        ## New Session

        | Image | Scenario |
        | --- | --- |
        \(table(newSessionRows))
        """
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    #endif

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
                        async let flows: Void = state.loadProjectFlows(project.id, force: true)
                        async let scripts: Void = state.loadProjectScripts(project.id, force: true)
                        _ = await (flows, scripts)
                        finished = true
                    }
                    let deadline = Date().addingTimeInterval(20)
                    while !finished && Date() < deadline {
                        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    }
                }
                if requestedProjectMode == .structure {
                    var finished = false
                    Task { @MainActor in
                        await state.loadProjectFiles(project.id, force: true)
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

#if DEBUG
/// Deterministic data for the session-sheet gallery.
private struct SheetGalleryFixtures {
    let project: Project
    let session: Session
    let failure: FailedTurn
    let failureWithError: FailedTurn
    let models: [ModelInfo]
    let agents: [AgentInfo]
    let selectedChoice: ModelChoice
    let alternateChoice: ModelChoice

    let prompt = """
    Bring the phone dark palette in line with the macOS tray panel. Check the running row, chips and dock, then update the screenshots.
    """
    let longPrompt = """
    Bring the phone dark palette in line with the macOS tray panel. Check the running row, chips and dock, then update the screenshots. Also verify the model picker, variant chips, agent choices, queued prompt banner, and the empty/loading/error states on both macOS and iOS. Keep the retry sheet's destination picker and failure card intact, and make sure the New Session sheet uses the same catalog loading and selection validation.
    """
    let longError = """
    This Go model trains on request data. Allow paid endpoints that train on request data in your workspace's Privacy settings to use it, or choose a different model whose data-use policy you accept. OpenCodeBar never changes provider privacy settings or enables training on request data.
    """

    init() {
        let now = Date().timeIntervalSince1970 * 1000
        let model = ModelRef(id: "deepseek-v4.1-flash", providerID: "opencode-go", variant: "high")
        let choice = ModelChoice(providerID: model.providerID, modelID: model.id)

        selectedChoice = choice
        alternateChoice = ModelChoice(providerID: "opencode-go", modelID: "kimi-k2.5")
        project = Project(
            id: "proj_ai_tools",
            canonical: "/Users/olivermolnar/Developer/ai-tools",
            vcs: "git",
            name: "ai-tools",
            time: .init(created: now - 86_400_000, updated: now, active: now),
            sandboxes: []
        )

        session = Session(
            id: "ses_preview_retry",
            parentID: nil,
            projectID: project.id,
            agent: "build",
            model: model,
            cost: 0.18,
            tokens: TokenUsage(
                input: 12_480,
                output: 3_210,
                reasoning: 1_120,
                cache: .init(read: 42_000, write: 8_400)
            ),
            outcome: "failed",
            time: .init(
                created: now - 600_000,
                updated: now,
                idle: nil,
                viewed: nil,
                archived: nil
            ),
            title: "Match iPhone dark theme",
            subpath: nil,
            fork: nil,
            task: nil,
            control: nil,
            location: .init(directory: project.canonical)
        )

        let promptMessage = SessionMessage(
            id: "msg_preview_prompt",
            type: "user",
            time: .init(created: now - 60_000, streamed: nil, completed: nil),
            text: prompt,
            files: nil,
            content: nil,
            model: nil,
            agent: nil,
            cost: nil,
            tokens: nil,
            outcome: nil,
            finish: nil,
            error: nil,
            retry: nil
        )

        let error = SessionMessageError(
            type: "provider_error",
            message: "HTTP 429 · rate limit exceeded. Please try again in 18s.",
            status: 429,
            response: .init(body: "Rate limit reached for requests. Please try again in 18s."),
            retryAfterMs: 18_000
        )
        let retry = SessionMessageRetry(attempt: 2, at: now, error: error)

        let failedMessage = SessionMessage(
            id: "msg_preview_error",
            type: "assistant",
            time: .init(created: now, streamed: nil, completed: nil),
            text: nil,
            files: nil,
            content: [],
            model: model,
            agent: "build",
            cost: 0,
            tokens: nil,
            outcome: "failed",
            finish: nil,
            error: error,
            retry: retry
        )
        let cleanMessage = SessionMessage(
            id: "msg_preview_idle",
            type: "assistant",
            time: .init(created: now, streamed: nil, completed: nil),
            text: nil,
            files: nil,
            content: [],
            model: model,
            agent: "build",
            cost: 0,
            tokens: nil,
            outcome: "interrupted",
            finish: nil,
            error: nil,
            retry: nil
        )

        failure = FailedTurn(
            message: cleanMessage,
            prompt: promptMessage,
            model: model,
            agent: "build"
        )
        failureWithError = FailedTurn(
            message: failedMessage,
            prompt: promptMessage,
            model: model,
            agent: "build"
        )

        models = [
            ModelInfo(
                id: "deepseek-v4.1-flash",
                modelID: "deepseek-v4.1-flash",
                providerID: "opencode-go",
                name: "DeepSeek V4.1 Flash",
                enabled: true,
                status: "active",
                variants: [
                    .init(id: "high", name: "High"),
                    .init(id: "max", name: "Max"),
                ],
                cost: ModelInfo.Cost(input: 0, output: 0),
                limit: ModelInfo.Limit(context: 1_048_576, output: 65_536)
            ),
            ModelInfo(
                id: "kimi-k2.5",
                modelID: "kimi-k2.5",
                providerID: "opencode-go",
                name: "Kimi K2.5",
                enabled: true,
                status: "active",
                variants: [
                    .init(id: "high", name: "High"),
                ],
                cost: ModelInfo.Cost(input: 0.6, output: 2.4),
                limit: ModelInfo.Limit(context: 262_144, output: 32_768)
            ),
            ModelInfo(
                id: "claude-sonnet-4.5",
                modelID: "claude-sonnet-4.5",
                providerID: "anthropic",
                name: "Claude Sonnet 4.5",
                enabled: true,
                status: "active",
                variants: nil,
                limit: ModelInfo.Limit(context: 200_000, output: 64_000)
            ),
            ModelInfo(
                id: "qwen3.5-coder",
                modelID: "qwen3.5-coder",
                providerID: "ollama",
                name: "Qwen3.5 Coder",
                enabled: true,
                status: "active",
                variants: nil,
                limit: ModelInfo.Limit(context: 32_768, output: 8_192)
            ),
        ]

        agents = [
            AgentInfo(id: "build", name: "build", mode: "primary", hidden: false, description: nil, model: nil),
            AgentInfo(id: "plan", name: "plan", mode: "primary", hidden: false, description: nil, model: nil),
            AgentInfo(id: "review", name: "review", mode: "primary", hidden: false, description: nil, model: nil),
        ]
    }
}
#endif

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
