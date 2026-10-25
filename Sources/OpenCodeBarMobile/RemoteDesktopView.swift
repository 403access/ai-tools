import SwiftUI
import UIKit

/// Remote desktop for the phone. The Mac captures one display with
/// ScreenCaptureKit; the hub relays JPEG frames and the phone sends pointer,
/// scroll, and keyboard input back.
struct RemoteDesktopView: View {
    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var connection = RemoteDesktopConnection()
    @State private var quality: RemoteQuality = .balanced
    @State private var keyboardActive = false
    @State private var rightClick = false
    @State private var zoomToken = 0
    @State private var showDetails = false

    var body: some View {
        Group {
            if !settings.isConfigured {
                ScrollView {
                    SetupPrompt(
                        title: "Connect to your Mac",
                        message: "Pair with the hub on your Mac to see and control its screen from here."
                    )
                    .padding(16)
                }
            } else {
                content
            }
        }
        .mobileScreenBackground()
        .navigationTitle("Remote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if connection.state.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button {
                    toggleConnection()
                } label: {
                    Image(
                        systemName: connection.state.isConnected
                            ? "stop.circle"
                            : "play.circle"
                    )
                }
                .disabled(store.api == nil)
                .accessibilityLabel(
                    connection.state.isConnected ? "Disconnect" : "Connect"
                )

                Menu {
                    qualityMenu
                    displayMenu
                    Divider()
                    Button {
                        Task { await requestScreenRecording() }
                    } label: {
                        Label("Request Screen Recording", systemImage: "rectangle.dashed")
                    }
                    Button {
                        Task { await requestAccessibility() }
                    } label: {
                        Label("Request Accessibility", systemImage: "hand.point.up.left")
                    }
                    Divider()
                    Button {
                        Task { await reconnect() }
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise")
                    }
                    Button {
                        showDetails = true
                    } label: {
                        Label("Connection details", systemImage: "info.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { await connectIfNeeded() }
        .onDisappear {
            keyboardActive = false
            connection.disconnect()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await connectIfNeeded() }
            case .background:
                keyboardActive = false
                connection.disconnect()
            default:
                break
            }
        }
        .sheet(isPresented: $showDetails) {
            RemoteDetailsSheet(
                status: connection.status,
                logs: connection.logs,
                state: connection.state
            )
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            statusStrip
            permissionBanner
            Divider().opacity(0.5)

            ZStack {
                Color.black
                if let image = connection.image {
                    RemoteDesktopSurface(
                        image: image,
                        imageSize: connection.imageSize,
                        isEnabled: connection.state.isConnected,
                        zoomToken: zoomToken,
                        onPointer: { action, x, y, _, clicks in
                            connection.pointer(
                                action,
                                x: x,
                                y: y,
                                button: rightClick ? "right" : "left",
                                clickCount: clicks
                            )
                        },
                        onScroll: { dx, dy, x, y in
                            connection.scroll(dx: dx, dy: dy, x: x, y: y)
                        }
                    )
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            if connection.state.isConnected || connection.state.isBusy {
                Divider().opacity(0.5)
                controls
            }
        }
        .overlay(alignment: .topLeading) {
            RemoteKeyboardInput(
                isActive: $keyboardActive,
                onText: { connection.sendText($0) },
                onDelete: { connection.sendKey("delete") },
                onReturn: { connection.sendKey("return") },
                onHardwareKey: handleHardwareKey
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(stateColor)
                .frame(width: 7, height: 7)

            Text(connection.state.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let status = connection.status, let display = status.display {
                Text("\(display.width)×\(display.height)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if connection.framesPerSecond > 0.5 {
                Text("\(Int(connection.framesPerSecond.rounded())) fps")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if connection.status?.accessibility == false {
                Label("View only", systemImage: "eye")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.warn)
            }

            if rightClick {
                Button {
                    rightClick = false
                } label: {
                    Text("Right")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.warn.opacity(0.18), in: Capsule())
                        .foregroundStyle(Theme.warn)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(MobileTheme.bar)
    }

    @ViewBuilder
    private var emptyState: some View {
        if let status = connection.status, !status.available {
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.warn)
                Text("Remote host not available")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(status.error ?? "The Mac's capture helper is not installed.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("make remote-host")
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.white)
                Text("Run that on the Mac, then restart the hub. `make hub` builds it automatically.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await reconnect() }
                } label: {
                    Label("Check again", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: 360)
        } else if let status = connection.status, !status.screenRecording {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.warn)
                Text("Allow Screen Recording")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text("macOS needs permission before OpenCodeBar Remote Host can capture the screen. The prompt appears on the Mac; enable it in System Settings → Privacy & Security → Screen Recording.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await requestScreenRecording() }
                } label: {
                    Label("Request on Mac", systemImage: "lock.open")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
            }
            .padding(24)
            .frame(maxWidth: 360)
        } else if connection.state.isBusy {
            VStack(spacing: 9) {
                ProgressView()
                Text("Starting capture on the Mac…")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "display")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white.opacity(0.45))
                Text(connection.state.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button {
                    toggleConnection()
                } label: {
                    Label("Connect", systemImage: "play.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(store.api == nil)
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private var permissionBanner: some View {
        if let status = connection.status, status.screenRecording, !status.accessibility {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.point.up.left")
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 3) {
                    Text("View only")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Allow Accessibility on the Mac to control the pointer and keyboard.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 2)
                Button {
                    Task { await requestAccessibility() }
                } label: {
                    Text("Allow")
                        .font(.caption2.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.warn)
                .controlSize(.mini)
            }
            .padding(10)
            .frame(maxWidth: 380)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
            .padding(.horizontal, 12)
        }
    }

    private var controls: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        zoomToken += 1
                    } label: {
                        controlLabel(
                            "Zoom",
                            icon: "arrow.up.left.and.arrow.down.right",
                            active: false
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        keyboardActive.toggle()
                    } label: {
                        controlLabel(
                            "Keyboard",
                            icon: "keyboard",
                            active: keyboardActive
                        )
                    }
                    .buttonStyle(.plain)

                    Divider().frame(height: 18)

                    ForEach(RemoteModifier.allCases) { modifier in
                        Button {
                            connection.toggle(modifier)
                        } label: {
                            Text(modifier.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 30, height: 27)
                                .background(
                                    connection.modifiers.contains(modifier)
                                        ? Theme.accent.opacity(0.24)
                                        : MobileTheme.field,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                                .foregroundStyle(
                                    connection.modifiers.contains(modifier)
                                        ? Theme.accent
                                        : Color.primary
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(modifier.title)
                    }

                    Divider().frame(height: 18)

                    ForEach(RemoteKey.allCases) { key in
                        Button {
                            connection.sendKey(key.rawValue)
                        } label: {
                            Text(key.label)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(minWidth: 30, minHeight: 27)
                                .padding(.horizontal, 2)
                                .background(
                                    MobileTheme.field,
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key.accessibility)
                    }

                    Divider().frame(height: 18)

                    Button {
                        rightClick.toggle()
                    } label: {
                        controlLabel(
                            "Right click",
                            icon: "cursorarrow.click.2",
                            active: rightClick
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                Text(quality.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if connection.state.isConnected {
                    Text(
                        connection.framesPerSecond > 0.5
                            ? "\(Int(connection.framesPerSecond.rounded())) fps"
                            : "Live"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                } else if connection.state.isBusy {
                    Text("Connecting")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                } else {
                    Text("Waiting")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Menu {
                    qualityMenu
                } label: {
                    Label("Quality", systemImage: "slider.horizontal.3")
                        .font(.caption2.weight(.semibold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 5)
        }
        .padding(.top, 5)
        .background(MobileTheme.bar)
    }

    private func controlLabel(_ title: String, icon: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background(
            active ? Theme.accent.opacity(0.2) : MobileTheme.field,
            in: RoundedRectangle(cornerRadius: 7)
        )
        .foregroundStyle(active ? Theme.accent : Color.primary)
    }

    @ViewBuilder
    private var qualityMenu: some View {
        Picker("Quality", selection: $quality) {
            ForEach(RemoteQuality.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .onChange(of: quality) { _, next in
            connection.configure(
                fps: next.fps,
                quality: next.quality,
                maxWidth: next.maxWidth
            )
        }
    }

    @ViewBuilder
    private var displayMenu: some View {
        if let displays = connection.status?.displays, displays.count > 1 {
            Menu {
                ForEach(displays) { display in
                    Button {
                        connection.selectDisplay(display.id)
                    } label: {
                        if display.id == connection.status?.displayID {
                            Label(display.name, systemImage: "checkmark")
                        } else {
                            Text(display.name)
                        }
                    }
                }
            } label: {
                Label("Display", systemImage: "display.2")
            }
        }
    }

    private var stateColor: Color {
        switch connection.state {
        case .connected: return Theme.accent
        case .connecting: return Theme.warn
        case .failed: return Theme.danger
        case .idle: return .secondary
        }
    }

    // MARK: - Actions

    private func connectIfNeeded() async {
        // The Host tab can appear before RootView's `store.start()` has created
        // the API client, especially when launched straight into Remote from a
        // deep link or a debug flag.
        for _ in 0..<20 where store.api == nil {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        guard let api = store.api else { return }
        guard connection.state.isConnected == false, connection.state.isBusy == false else {
            return
        }
        // The socket's first status message carries permissions and display
        // geometry, so there is no need to wait for a REST round trip before
        // connecting. This also works when the helper is still starting.
        connection.connect(api: api)
    }

    private func reconnect() async {
        guard let api = store.api else { return }
        connection.disconnect()
        try? await Task.sleep(nanoseconds: 300_000_000)
        connection.connect(api: api)
    }

    private func toggleConnection() {
        guard let api = store.api else { return }
        if connection.state.isConnected || connection.state.isBusy {
            connection.disconnect()
        } else {
            connection.connect(api: api)
        }
    }

    private func requestScreenRecording() async {
        guard let api = store.api else { return }
        // Keep the socket open while macOS waits for the toggle: the helper
        // retries capture and the first frame appears on its own.
        if connection.state.isConnected == false, connection.state.isBusy == false {
            connection.connect(api: api)
        }
        await connection.requestPermissions(screenRecording: true, accessibility: false)
    }

    private func requestAccessibility() async {
        await connection.requestPermissions(screenRecording: false, accessibility: true)
    }

    private func handleHardwareKey(_ key: UIKey) -> Bool {
        var modifiers: Set<RemoteModifier> = []
        let flags = key.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        if let name = Self.specialKeyName(key.keyCode) {
            connection.sendKey(name, modifiers: modifiers)
            return true
        }

        // Plain printable keys are left to the text field's normal insertion,
        // which runs through the delegate. Handling them here as well would
        // double-type every character on a hardware keyboard.
        if modifiers.intersection([.command, .control, .option]).isEmpty {
            return false
        }

        let name = key.charactersIgnoringModifiers.lowercased()
        guard !name.isEmpty else { return false }
        connection.sendKey(name, modifiers: modifiers)
        return true
    }

    private static func specialKeyName(_ usage: UIKeyboardHIDUsage) -> String? {
        switch usage {
        case .keyboardEscape: return "escape"
        case .keyboardTab: return "tab"
        case .keyboardReturnOrEnter: return "return"
        case .keyboardDeleteOrBackspace: return "delete"
        case .keyboardDeleteForward: return "forwarddelete"
        case .keyboardSpacebar: return "space"
        case .keyboardUpArrow: return "up"
        case .keyboardDownArrow: return "down"
        case .keyboardLeftArrow: return "left"
        case .keyboardRightArrow: return "right"
        case .keyboardHome: return "home"
        case .keyboardEnd: return "end"
        case .keyboardPageUp: return "pageup"
        case .keyboardPageDown: return "pagedown"
        case .keyboardF1: return "f1"
        case .keyboardF2: return "f2"
        case .keyboardF3: return "f3"
        case .keyboardF4: return "f4"
        case .keyboardF5: return "f5"
        case .keyboardF6: return "f6"
        case .keyboardF7: return "f7"
        case .keyboardF8: return "f8"
        case .keyboardF9: return "f9"
        case .keyboardF10: return "f10"
        case .keyboardF11: return "f11"
        case .keyboardF12: return "f12"
        default: return nil
        }
    }
}

enum RemoteQuality: String, CaseIterable, Identifiable {
    case sharp
    case balanced
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sharp: return "Sharp"
        case .balanced: return "Balanced"
        case .fast: return "Fast"
        }
    }

    var fps: Int {
        switch self {
        case .sharp: return 18
        case .balanced: return 12
        case .fast: return 8
        }
    }

    var quality: Double {
        switch self {
        case .sharp: return 0.72
        case .balanced: return 0.6
        case .fast: return 0.45
        }
    }

    var maxWidth: Int {
        switch self {
        case .sharp: return 1920
        case .balanced: return 1600
        case .fast: return 1280
        }
    }
}

enum RemoteKey: String, CaseIterable, Identifiable {
    case escape
    case tab
    case delete
    case enter = "return"
    case left
    case up
    case down
    case right

    var id: String { rawValue }

    var label: String {
        switch self {
        case .escape: return "esc"
        case .tab: return "tab"
        case .delete: return "⌫"
        case .enter: return "↩"
        case .left: return "←"
        case .up: return "↑"
        case .down: return "↓"
        case .right: return "→"
        }
    }

    var accessibility: String {
        switch self {
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .delete: return "Delete"
        case .enter: return "Return"
        case .left: return "Left arrow"
        case .up: return "Up arrow"
        case .down: return "Down arrow"
        case .right: return "Right arrow"
        }
    }
}

private struct RemoteDetailsSheet: View {
    let status: RemoteDesktopStatus?
    let logs: [String]
    let state: RemoteDesktopConnection.State

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    row("State", state.label)
                    if let status {
                        row("Helper", status.version ?? "unknown")
                        row("Streaming", status.streaming ? "Yes" : "No")
                        row("Viewers", "\(status.viewers)")
                        row("Capture", "\(status.fps) fps · \(Int(status.quality * 100))% · \(status.maxWidth) px")
                    }
                }

                if let status {
                    Section("Permissions") {
                        row("Screen Recording", status.screenRecording ? "Granted" : "Not granted")
                        row("Accessibility", status.accessibility ? "Granted" : "Not granted")
                    }

                    if !status.displays.isEmpty {
                        Section("Displays") {
                            ForEach(status.displays) { display in
                                row(
                                    display.name,
                                    "\(display.width)×\(display.height)\(display.primary ? " · main" : "")"
                                )
                            }
                        }
                    }

                    if let error = status.error, !error.isEmpty {
                        Section("Last error") {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Theme.warn)
                        }
                    }
                }

                if !logs.isEmpty {
                    Section("Log") {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Remote details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }
}

/// A one-pixel text field that owns the keyboard. Hardware key presses arrive
/// through `pressesBegan`; the software keyboard's insertions go through the
/// text field delegate so both paths produce the same remote key messages.
private struct RemoteKeyboardInput: UIViewRepresentable {
    @Binding var isActive: Bool
    var onText: (String) -> Void
    var onDelete: () -> Void
    var onReturn: () -> Void
    var onHardwareKey: (UIKey) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> RemoteKeyboardField {
        let field = RemoteKeyboardField()
        field.delegate = context.coordinator
        field.onHardwareKey = onHardwareKey
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.keyboardType = .asciiCapable
        field.textColor = .clear
        field.tintColor = .clear
        field.backgroundColor = .clear
        return field
    }

    func updateUIView(_ field: RemoteKeyboardField, context: Context) {
        context.coordinator.parent = self
        field.onHardwareKey = onHardwareKey
        if isActive, !field.isFirstResponder {
            DispatchQueue.main.async {
                field.becomeFirstResponder()
            }
        } else if !isActive, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RemoteKeyboardInput

        init(_ parent: RemoteKeyboardInput) {
            self.parent = parent
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if string.isEmpty {
                let count = max(range.length, 1)
                for _ in 0..<count { parent.onDelete() }
            } else {
                parent.onText(string)
            }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isActive {
                parent.isActive = false
            }
        }
    }
}

private final class RemoteKeyboardField: UITextField {
    var onHardwareKey: ((UIKey) -> Bool)?

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            if let key = press.key, onHardwareKey?(key) == true {
                handled = true
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }
}
