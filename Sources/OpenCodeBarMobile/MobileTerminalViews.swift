import SwiftUI

/// Terminals section for the phone's System tab. The Mac runs the PTYs; the
/// hub proxies their sockets so typing works over Wi-Fi or a tunnel.
struct MobileTerminalsSection: View {
    @EnvironmentObject private var store: MobileStore
    var onOpen: (SystemTerminal) -> Void
    var onNew: () -> Void

    @State private var showAll = false
    @State private var pendingStop: SystemTerminal?

    private var visible: [SystemTerminal] {
        showAll ? store.terminals : Array(store.terminals.prefix(6))
    }

    private var stopBinding: Binding<Bool> {
        Binding(
            get: { pendingStop != nil },
            set: { if !$0 { pendingStop = nil } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Terminals") {
                HStack(spacing: 9) {
                    if store.isRefreshingTerminals {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    }
                    if !store.terminals.isEmpty {
                        Text("\(store.terminals.count)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button(action: onNew) {
                        Label("New", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Interactive shells on the Mac. Open one to type into it; terminals started in OpenCode show up here too.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = store.terminalsError, store.terminals.isEmpty {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.warn)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if store.terminals.isEmpty {
                    HStack(spacing: 9) {
                        Image(systemName: "terminal")
                            .font(.title3.weight(.light))
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No terminals running")
                                .font(.caption.weight(.medium))
                            Text("Start one to get a shell in any project folder.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    ForEach(visible) { terminal in
                        MobileTerminalRow(
                            terminal: terminal,
                            onOpen: { onOpen(terminal) },
                            onRemove: { pendingStop = terminal }
                        )
                        if terminal.id != visible.last?.id {
                            Divider().opacity(0.45)
                        }
                    }

                    if store.terminals.count > 6 {
                        Button(showAll ? "Show fewer" : "Show all \(store.terminals.count) terminals") {
                            showAll.toggle()
                        }
                        .font(.caption.weight(.semibold))
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
                Task { try? await store.removeTerminal(terminal) }
            }
            Button("Cancel", role: .cancel) { pendingStop = nil }
        } message: {
            Text("The shell and anything running in it will be terminated.")
        }
    }
}

private struct MobileTerminalRow: View {
    let terminal: SystemTerminal
    var onOpen: () -> Void
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onOpen) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(terminal.isRunning ? Theme.accent : Color.secondary.opacity(0.45))
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(terminal.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            if !terminal.isRunning {
                                Text(terminal.exitCode.map { "exit \($0)" } ?? "exited")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Theme.warn)
                            }
                        }
                        Text(terminal.cwdLabel)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the terminal")

            Button(action: onRemove) {
                Image(systemName: "stop.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop \(terminal.title)")
        }
    }
}

/// Starts a terminal from the phone, using a project folder or a custom path.
struct MobileNewTerminalSheet: View {
    @EnvironmentObject private var store: MobileStore
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    if !store.orderedProjects.isEmpty {
                        Picker("Project", selection: $directory) {
                            ForEach(store.orderedProjects) { project in
                                Text(project.displayName).tag(project.canonical)
                            }
                        }
                    }
                    TextField("Project directory", text: $directory)
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Title") {
                    TextField("Optional", text: $title)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.warn)
                    }
                }

                Section {
                    Text("The shell starts on the Mac, in the folder above. OpenCode terminals and this one share the same machine.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Terminal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Start")
                        }
                    }
                    .disabled(isWorking || trimmedDirectory.isEmpty)
                }
            }
            .onAppear {
                if trimmedDirectory.isEmpty {
                    directory = store.orderedProjects.first?.canonical ?? ""
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submit() async {
        guard !isWorking, !trimmedDirectory.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        do {
            let terminal = try await store.createTerminal(
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

/// Full-screen terminal sheet for the phone. The command field is a convenient
/// way to run a line without summoning SwiftTerm's on-screen keyboard first.
struct MobileTerminalDetailView: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let terminal: SystemTerminal
    @StateObject private var connection: TerminalConnection
    @State private var command = ""
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
        NavigationStack {
            VStack(spacing: 0) {
                statusStrip
                Divider()

                if terminal.isRunning {
                    TerminalEmulatorView(connection: connection)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    exitedState
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }

                if terminal.isRunning {
                    Divider()
                    commandBar
                }
            }
            .background(Color(red: 0.052, green: 0.062, blue: 0.085))
            .navigationTitle(terminal.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if terminal.isRunning, !connection.state.isConnected {
                        Button {
                            connection.connect()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Reconnect")
                    }
                    if isStopping {
                        ProgressView().controlSize(.small)
                    }
                    Button(role: .destructive) {
                        confirmStop = true
                    } label: {
                        Image(systemName: "stop.circle")
                    }
                    .disabled(isStopping)
                    .accessibilityLabel("Stop terminal")
                }
            }
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
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(terminal.isRunning ? Theme.accent : Color.secondary)
                .frame(width: 6, height: 6)
            Text(connection.state.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(terminal.cwdLabel)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("pid \(terminal.pid)")
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var exitedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.largeTitle.weight(.light))
                .foregroundStyle(.tertiary)
            Text("This terminal has exited")
                .font(.callout.weight(.semibold))
            Text(terminal.exitCode.map { "Exit code \($0)" } ?? "The shell is no longer running.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            TextField("Send a command", text: $command)
                .font(.system(size: 13, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit(sendCommand)

            Button(action: sendCommand) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(!connection.state.isConnected)
            .accessibilityLabel("Send command")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MobileTheme.bar)
    }

    private func sendCommand() {
        let line = command
        command = ""
        connection.submit(line)
    }

    private func stop() async {
        isStopping = true
        errorMessage = nil
        do {
            try await store.removeTerminal(terminal)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isStopping = false
    }
}
