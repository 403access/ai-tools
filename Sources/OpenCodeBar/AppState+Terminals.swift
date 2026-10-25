import Foundation

/// Terminals live behind their own endpoint rather than inside the system
/// snapshot: they change on their own and should not make the machine
/// inventory wait on OpenCode.
extension AppState {
    func refreshTerminals(force: Bool = false) async {
        if api == nil { await bootstrap() }
        guard let api else { return }
        guard !isRefreshingTerminals else { return }
        if !force, let fetched = terminalsFetchedAt,
           Date().timeIntervalSince(fetched) < 3 {
            return
        }

        isRefreshingTerminals = true
        defer { isRefreshingTerminals = false }

        do {
            terminals = try await api.terminals(force: force)
            terminalsFetchedAt = Date()
            terminalsError = nil
        } catch {
            if let apiError = error as? APIError, case .request(404, _) = apiError {
                terminalsError = "This hub does not serve terminals yet. Restart it with the latest code."
            } else if terminals.isEmpty {
                terminalsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            // Keep the last list while the hub or OpenCode reconnects.
        }
    }

    /// Starts a shell in `directory`; the returned terminal is immediately
    /// added to the list so the caller can open it without waiting for a poll.
    func createTerminal(title: String, directory: String) async throws -> SystemTerminal {
        if api == nil { await bootstrap() }
        guard let api else { throw APIError.transport("Not connected to the hub") }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let terminal = try await api.createTerminal(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            cwd: directory.isEmpty ? nil : directory,
            location: directory
        )
        if let index = terminals.firstIndex(where: { $0.id == terminal.id }) {
            terminals[index] = terminal
        } else {
            terminals.insert(terminal, at: 0)
        }
        terminalsFetchedAt = Date()
        terminalsError = nil
        return terminal
    }

    /// Stops the shell and removes its PTY from the list.
    func removeTerminal(_ terminal: SystemTerminal) async throws {
        guard let api else { return }
        try await api.removeTerminal(id: terminal.id, location: terminal.location)
        terminals.removeAll { $0.id == terminal.id }
        terminalsFetchedAt = Date()
    }
}
