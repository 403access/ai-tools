import Foundation

/// Polls the hub for a Terminal.app tab's plain-text screen and sends commands
/// back to the same tab. macOS does not expose a PTY master for existing
/// terminals, so this is the closest equivalent to attaching: a one-second
/// mirror plus line-based input.
@MainActor
final class HostTerminalMirror: ObservableObject {
    enum State: Equatable {
        case loading
        case ready
        case unavailable(String)
    }

    let api: HubAPI
    let terminal: HostTerminal

    @Published private(set) var detail: HostTerminalDetail?
    @Published private(set) var state: State = .loading
    @Published private(set) var isSending = false
    @Published private(set) var lastUpdated: Date?
    @Published var actionError: String?

    private var pollTask: Task<Void, Never>?
    private var isRefreshing = false

    init(api: HubAPI, terminal: HostTerminal) {
        self.api = api
        self.terminal = terminal
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let fetched = try await api.hostTerminal(id: terminal.id)
            if detail != fetched {
                detail = fetched
            }
            state = .ready
            lastUpdated = Date()
            actionError = nil
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if detail == nil {
                state = .unavailable(message)
            } else {
                actionError = message
            }
        }
    }

    /// Sends a complete line, exactly like typing it and pressing Return. An
    /// empty string presses Return on its own.
    func send(_ command: String) async {
        guard !isSending else { return }
        isSending = true
        actionError = nil
        defer { isSending = false }

        do {
            try await api.sendHostTerminalCommand(id: terminal.id, command: command)
            // Give the tab a moment to echo the command before polling again.
            try? await Task.sleep(nanoseconds: 250_000_000)
            await refresh()
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func focus() async {
        do {
            try await api.focusHostTerminal(id: terminal.id)
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
