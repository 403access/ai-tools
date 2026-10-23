import SwiftUI

extension SessionDetailView {
    // MARK: - Loading

    func loadLatest() async {
        guard !isFetchingLatest else { return }
        isFetchingLatest = true
        if messages.isEmpty { isLoading = true }
        defer {
            isLoading = false
            isFetchingLatest = false
        }

        do {
            // The first page needs enough history to fill the view; later
            // refreshes only need the newest window, which is where streaming
            // output lands.
            let limit = messages.isEmpty ? 100 : 30
            let response = try await state.messages(for: session.id, limit: limit)
            guard !Task.isCancelled else { return }

            // Keep any older pages the user already loaded; refresh the newest
            // page in place so live tool output updates without losing scroll.
            let fresh = response.data
            let freshIDs = Set(fresh.map(\.id))
            let cutoff = fresh.map(\.time.created).min()
            let retained = messages.filter { message in
                guard !freshIDs.contains(message.id), let cutoff else { return false }
                return message.time.created < cutoff
            }

            let merged = MessageOrdering.mostRecentFirst(fresh + retained)
            if merged != messages { messages = merged }
            if retained.isEmpty {
                previousCursor = response.cursor?.previous
            }
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if messages.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadEarlier() async {
        guard let cursor = previousCursor, !isLoadingEarlier else { return }
        isLoadingEarlier = true
        earlierError = nil
        defer { isLoadingEarlier = false }

        do {
            let response = try await state.messages(for: session.id, limit: 100, cursor: cursor)
            guard !Task.isCancelled else { return }

            let existing = Set(messages.map(\.id))
            let older = response.data.filter { !existing.contains($0.id) }
            messages = MessageOrdering.mostRecentFirst(messages + older)
            previousCursor = response.cursor?.previous
        } catch {
            guard !Task.isCancelled else { return }
            earlierError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
