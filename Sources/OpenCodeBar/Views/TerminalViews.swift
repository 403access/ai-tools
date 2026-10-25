import AppKit
import SwiftUI

/// Terminal list shown in the System tab. Terminals are OpenCode PTYs, so the
/// list includes shells started from OpenCode's own terminal panel as well as
/// the ones started here.
struct TerminalsSection: View {
    @EnvironmentObject private var state: AppState
    var onOpen: (SystemTerminal) -> Void
    var onNew: () -> Void

    @State private var showAll = false
    @State private var pendingStop: SystemTerminal?

    private var visible: [SystemTerminal] {
        showAll ? state.terminals : Array(state.terminals.prefix(8))
    }

    private var stopBinding: Binding<Bool> {
        Binding(
            get: { pendingStop != nil },
            set: { if !$0 { pendingStop = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("OpenCode Terminals") {
                HStack(spacing: 8) {
                    if state.isRefreshingTerminals {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    }
                    if !state.terminals.isEmpty {
                        Text("\(state.terminals.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button(action: onNew) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                            Text("New")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .help("Start a shell on the machine running the hub")
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Interactive shells on the hub host. Open one to type into it; terminals started in OpenCode appear here too.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = state.terminalsError, state.terminals.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.warn)
                        Text(error)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if state.terminals.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("No terminals running")
                                .font(.system(size: 10, weight: .medium))
                            Text("Start one to get a shell in any project folder.")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(visible) { terminal in
                        TerminalRow(
                            terminal: terminal,
                            onOpen: { onOpen(terminal) },
                            onRemove: { pendingStop = terminal }
                        )
                    }

                    if state.terminals.count > 8 {
                        Button(showAll ? "Show fewer" : "Show all \(state.terminals.count) terminals") {
                            showAll.toggle()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .card()
        }
        .confirmationDialog(
            "Stop “\(pendingStop?.title ?? "terminal")”?",
            isPresented: stopBinding,
            titleVisibility: .visible
        ) {
            Button("Stop terminal", role: .destructive) {
                guard let terminal = pendingStop else { return }
                pendingStop = nil
                Task { try? await state.removeTerminal(terminal) }
            }
            Button("Cancel", role: .cancel) { pendingStop = nil }
        } message: {
            Text("The shell and anything running in it will be terminated.")
        }
    }
}

private struct TerminalRow: View {
    let terminal: SystemTerminal
    var onOpen: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(terminal.isRunning ? Theme.accent : Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(terminal.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .lineLimit(1)
                            if !terminal.isRunning {
                                Text(terminal.exitCode.map { "exit \($0)" } ?? "exited")
                                    .font(.system(size: 7.5, weight: .bold))
                                    .tracking(0.4)
                                    .foregroundStyle(Theme.warn)
                            }
                        }
                        Text(terminal.commandLine)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(terminal.cwdLabel)
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text((terminal.location as NSString).lastPathComponent)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text("pid \(terminal.pid)")
                            .font(.system(size: 7.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(terminal.title) · \(terminal.cwd)")

            Button(action: onRemove) {
                Image(systemName: "stop.circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop this terminal")
            .accessibilityLabel("Stop \(terminal.title)")
        }
        .padding(.vertical, 2)
    }
}

/// Terminal.app tabs already open on the hub host. macOS automation exposes
/// their text and lets the hub run commands in them, so they are a separate
/// group from OpenCode's own PTYs.
struct HostTerminalsSection: View {
    @EnvironmentObject private var state: AppState
    var onOpen: (HostTerminal) -> Void

    @State private var showAll = false

    private var visible: [HostTerminal] {
        showAll ? state.hostTerminals : Array(state.hostTerminals.prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Terminal.app") {
                HStack(spacing: 8) {
                    if state.isRefreshingHostTerminals {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    }
                    if !state.hostTerminals.isEmpty {
                        Text("\(state.hostTerminals.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("Tabs already open in Terminal.app on the hub host. Open one to mirror its screen and run commands in it.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = state.hostTerminalsError, state.hostTerminals.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.warn)
                        Text(error)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if state.hostTerminals.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 14, weight: .light))
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("No Terminal.app tabs")
                                .font(.system(size: 10, weight: .medium))
                            Text("Open a Terminal window on the Mac and it appears here.")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(visible) { terminal in
                        HostTerminalRow(terminal: terminal) {
                            onOpen(terminal)
                        }
                    }

                    if state.hostTerminals.count > 6 {
                        Button(showAll ? "Show fewer" : "Show all \(state.hostTerminals.count) tabs") {
                            showAll.toggle()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .card()
        }
    }
}

private struct HostTerminalRow: View {
    let terminal: HostTerminal
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Circle()
                    .fill(terminal.busy ? Theme.accent : Color.secondary.opacity(0.45))
                    .frame(width: 6, height: 6)

                VStack(alignment: .leading, spacing: 1) {
                    Text(terminal.displayTitle)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(terminal.processLabel) · \(terminal.tty)")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Text(terminal.locationLabel)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Mirror \(terminal.tty)")
    }
}

/// Mirrors one Terminal.app tab. The text is polled once a second; the command
/// field sends a complete line through the same tab.
struct HostTerminalDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let terminal: HostTerminal
    @StateObject private var mirror: HostTerminalMirror
    @State private var command = ""
    @FocusState private var commandFocused: Bool

    init(terminal: HostTerminal, api: HubAPI) {
        self.terminal = terminal
        _mirror = StateObject(
            wrappedValue: HostTerminalMirror(api: api, terminal: terminal)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mirrorBody
            Divider()
            commandBar

            if let error = mirror.actionError {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn)
                    Text(error)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .frame(
            minWidth: 780,
            idealWidth: 920,
            maxWidth: 1_200,
            minHeight: 540,
            idealHeight: 680,
            maxHeight: 1_000
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            mirror.start()
            commandFocused = true
        }
        .onDisappear { mirror.stop() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "macwindow")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(mirror.detail?.title ?? terminal.displayTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(terminal.processLabel) · \(terminal.tty) · window \(mirror.detail?.window ?? terminal.window)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Chip(
                text: (mirror.detail?.busy ?? terminal.busy) ? "running" : "idle",
                systemImage: "circle.fill",
                tint: (mirror.detail?.busy ?? terminal.busy) ? Theme.accent : .secondary
            )

            if let updated = mirror.lastUpdated {
                Text("Updated \(Fmt.relative(from: updated))")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button {
                Task { await mirror.focus() }
            } label: {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Focus this tab on the Mac")

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var mirrorBody: some View {
        Group {
            if let detail = mirror.detail {
                ScrollView {
                    Text(detail.displayText.isEmpty ? "Waiting for output…" : detail.displayText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(red: 0.87, green: 0.91, blue: 0.95))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .defaultScrollAnchor(.bottom)
                .background(Color(red: 0.052, green: 0.062, blue: 0.085))
            } else if case .unavailable(let message) = mirror.state {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Theme.warn)
                    Text("Terminal.app is unavailable")
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    Button("Try again") {
                        Task { await mirror.refresh() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Reading Terminal.app…")
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                TextField("Run a command in this tab", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .focused($commandFocused)
                    .onSubmit(run)

                if mirror.isSending {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                }

                Button("Run", action: run)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(mirror.isSending)
            }

            Text("Commands run in the existing tab, like typing a line and pressing Return. Leave the field empty to press Return.")
                .font(.system(size: 8.5))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func run() {
        let line = command
        command = ""
        Task { await mirror.send(line) }
    }
}

/// Starts a new shell through the hub. The created terminal opens immediately
/// so the user can start typing without another click.
struct NewTerminalSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var onCreated: (SystemTerminal) -> Void

    @State private var directory: String
    @State private var title = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(directory: String? = nil, onCreated: @escaping (SystemTerminal) -> Void) {
        _directory = State(initialValue: directory ?? "")
        self.onCreated = onCreated
    }

    private var trimmedDirectory: String {
        directory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var projectLabel: String {
        state.orderedProjects.first(where: { $0.canonical == trimmedDirectory })?.displayName
            ?? "Custom directory"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New terminal")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Starts the hub host's shell in the folder you pick.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .disabled(isWorking)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("PROJECT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                if !state.orderedProjects.isEmpty {
                    Picker("Project", selection: $directory) {
                        ForEach(state.orderedProjects) { project in
                            Text(project.displayName).tag(project.canonical)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(isWorking)
                }

                TextField("Project directory", text: $directory)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .disabled(isWorking)

                if !trimmedDirectory.isEmpty {
                    Text(projectLabel == "Custom directory" ? trimmedDirectory : projectLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("TITLE · OPTIONAL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                TextField("Defaults to the shell's name", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(isWorking)
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn)
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(padding: 8)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Start terminal") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isWorking || trimmedDirectory.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 390)
        .onAppear {
            if trimmedDirectory.isEmpty {
                directory = state.orderedProjects.first?.canonical ?? ""
            }
        }
        .onExitCommand { dismiss() }
    }

    private func submit() async {
        guard !isWorking, !trimmedDirectory.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        do {
            let terminal = try await state.createTerminal(
                title: title,
                directory: trimmedDirectory
            )
            dismiss()
            onCreated(terminal)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }
}

/// Full terminal window content presented as a sheet from the System tab.
struct TerminalDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let terminal: SystemTerminal
    @StateObject private var connection: TerminalConnection
    @State private var confirmStop = false
    @State private var isStopping = false
    @State private var errorMessage: String?

    init(terminal: SystemTerminal, api: HubAPI) {
        self.terminal = terminal
        _connection = StateObject(
            wrappedValue: TerminalConnection(api: api, terminal: terminal)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if terminal.isRunning {
                TerminalEmulatorView(connection: connection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                exitedState
            }

            if let errorMessage {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn)
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Stop “\(terminal.title)”?",
            isPresented: $confirmStop,
            titleVisibility: .visible
        ) {
            Button("Stop terminal", role: .destructive) {
                Task { await stop() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The shell and anything running in it will be terminated.")
        }
        .onDisappear { connection.disconnect() }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "terminal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(terminal.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(terminal.cwdLabel)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Chip(
                text: connection.state.label,
                systemImage: statusIcon,
                tint: statusTint
            )

            if terminal.isRunning, !connection.state.isConnected {
                Button {
                    connection.connect()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reconnect")
            }

            Button {
                copy(terminal.cwd)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy working directory")

            if isStopping {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }

            Button {
                confirmStop = true
            } label: {
                Image(systemName: "stop.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.warn)
            .disabled(isStopping)
            .help("Stop terminal")

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var exitedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("This terminal has exited")
                .font(.system(size: 12, weight: .semibold))
            Text(terminal.exitCode.map { "Exit code \($0)" } ?? "The shell is no longer running.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusIcon: String {
        if terminal.isRunning == false { return "xmark.circle.fill" }
        switch connection.state {
        case .connected: return "circle.fill"
        case .connecting: return "circle.dotted"
        case .disconnected: return "exclamationmark.circle"
        case .exited: return "xmark.circle.fill"
        }
    }

    private var statusTint: Color {
        if terminal.isRunning == false { return Theme.warn }
        switch connection.state {
        case .connected: return Theme.accent
        case .connecting: return Theme.running
        case .disconnected: return Theme.warn
        case .exited: return Theme.warn
        }
    }

    private func copy(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func stop() async {
        isStopping = true
        errorMessage = nil
        do {
            try await state.removeTerminal(terminal)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isStopping = false
    }
}
