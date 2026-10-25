import Foundation

/// Terminal state for the phone. The hub exposes the Mac's OpenCode PTYs, so
/// the same list and sockets the desktop app uses work over the LAN or tunnel.
extension MobileStore {
    func refreshTerminals(force: Bool = false) async {
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
        }
    }

    func createTerminal(title: String, directory: String) async throws -> SystemTerminal {
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

    func removeTerminal(_ terminal: SystemTerminal) async throws {
        guard let api else { return }
        try await api.removeTerminal(id: terminal.id, location: terminal.location)
        terminals.removeAll { $0.id == terminal.id }
        terminalsFetchedAt = Date()
    }
}
