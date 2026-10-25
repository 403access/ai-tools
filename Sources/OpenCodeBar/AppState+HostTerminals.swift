import Foundation

/// Terminal.app tabs are separate from OpenCode's PTYs: the hub reads them with
/// macOS automation, so they can fail independently (for example when the
/// Automation permission has not been granted).
extension AppState {
    func refreshHostTerminals(force: Bool = false) async {
        if api == nil { await bootstrap() }
        guard let api else { return }
        guard !isRefreshingHostTerminals else { return }
        if !force, let fetched = hostTerminalsFetchedAt,
           Date().timeIntervalSince(fetched) < 3 {
            return
        }

        isRefreshingHostTerminals = true
        defer { isRefreshingHostTerminals = false }

        do {
            let fetched = try await api.hostTerminals(force: force)
            hostTerminals = fetched
            hostTerminalsFetchedAt = Date()
            hostTerminalsError = nil
        } catch {
            if let apiError = error as? APIError, case .request(404, _) = apiError {
                hostTerminalsError = "This hub does not serve Terminal.app tabs yet. Restart it with the latest code."
            } else if hostTerminals.isEmpty {
                hostTerminalsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            // Keep the last list while the hub or Terminal.app reconnects.
        }
    }
}
