import Foundation

/// Terminal.app tabs on the Mac, mirrored through the hub. Commands run in the
/// existing tab; the phone only needs the hub token.
extension MobileStore {
    func refreshHostTerminals(force: Bool = false) async {
        guard let api else { return }
        guard !isRefreshingHostTerminals else { return }
        if !force, let fetched = hostTerminalsFetchedAt,
           Date().timeIntervalSince(fetched) < 3 {
            return
        }

        isRefreshingHostTerminals = true
        defer { isRefreshingHostTerminals = false }

        do {
            hostTerminals = try await api.hostTerminals(force: force)
            hostTerminalsFetchedAt = Date()
            hostTerminalsError = nil
        } catch {
            if let apiError = error as? APIError, case .request(404, _) = apiError {
                hostTerminalsError = "This hub does not serve Terminal.app tabs yet. Restart it with the latest code."
            } else if hostTerminals.isEmpty {
                hostTerminalsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
