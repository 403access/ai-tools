import Foundation

extension AppState {
    // MARK: - Forks

    func forkList(for sessionID: String) -> ForkList? {
        forkLists[sessionID]
    }

    func hasForks(_ sessionID: String) -> Bool {
        !(forkLists[sessionID]?.sessions.isEmpty ?? true)
    }

    /// The known row for a session id, looking beyond the live list so a fork
    /// can link to an older source conversation.
    func knownSession(id: String) -> Session? {
        sessions.first { $0.id == id }
            ?? history.first { $0.id == id }
            ?? forkLists.values
                .lazy
                .flatMap(\.sessions)
                .first { $0.id == id }
    }

    /// Fetches one session that is not in the live list, for a fork's source.
    func fetchSession(id: String) async -> Session? {
        if let known = knownSession(id: id) { return known }
        guard let api, let fetched = try? await api.session(id: id) else { return nil }
        if !sessions.contains(where: { $0.id == fetched.id }) {
            history.append(fetched)
        }
        return fetched
    }

    /// Loads the sessions forked from one conversation.
    func loadForks(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if forkLists[sessionID]?.isLoading == true { return }
        if !force, let loaded = forkLists[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 30 {
            return
        }
        defer { trimCache(&forkLists, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var list = forkLists[sessionID] ?? ForkList()
        list.isLoading = true
        list.error = nil
        forkLists[sessionID] = list

        do {
            let forks = try await api.sessionForks(id: sessionID)
            forkLists[sessionID] = ForkList(
                sessions: forks.sorted { $0.time.updated > $1.time.updated },
                loadedAt: Date()
            )
        } catch {
            var failed = forkLists[sessionID] ?? ForkList()
            failed.isLoading = false
            if Task.isCancelled {
                forkLists[sessionID] = failed
                return
            }
            failed.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            forkLists[sessionID] = failed
        }
    }

    /// Folds the five-second session list into any open fork lists so titles,
    /// running state, and cost stay current without a second fetch.
    func syncForkLists(with sessions: [Session]) {
        for sourceID in Array(forkLists.keys) {
            guard var list = forkLists[sourceID] else { continue }
            var changed = false

            for session in sessions where session.fork?.sessionID == sourceID {
                if let index = list.sessions.firstIndex(where: { $0.id == session.id }) {
                    if list.sessions[index] != session {
                        list.sessions[index] = session
                        changed = true
                    }
                } else {
                    list.sessions.append(session)
                    changed = true
                }
            }

            if changed {
                list.sessions.sort { $0.time.updated > $1.time.updated }
                forkLists[sourceID] = list
            }
        }
    }
}
