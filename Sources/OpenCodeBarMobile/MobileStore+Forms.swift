import Combine
import Foundation

extension MobileStore {
    // MARK: - Question forms

    /// Fetches the forms waiting for an answer in a session. The list only
    /// contains pending forms; answered questions live in the tool result.
    func loadForms(_ sessionID: String, force: Bool = false) async {
        guard let api else { return }
        if sessionForms[sessionID]?.isLoading == true { return }
        if !force, let loaded = sessionForms[sessionID]?.loadedAt,
           Date().timeIntervalSince(loaded) < 5 {
            return
        }
        defer { trimCache(&sessionForms, loadedAt: { $0.loadedAt }, pinning: sessionID) }

        var state = sessionForms[sessionID] ?? FormListState()
        state.isLoading = true
        state.error = nil
        sessionForms[sessionID] = state

        do {
            let forms = try await api.sessionForms(id: sessionID)
            sessionForms[sessionID] = FormListState(forms: forms, loadedAt: Date())
        } catch {
            var failed = sessionForms[sessionID] ?? FormListState()
            failed.isLoading = false
            failed.loadedAt = Date()
            if Task.isCancelled {
                sessionForms[sessionID] = failed
                return
            }
            failed.error = message(for: error)
            sessionForms[sessionID] = failed
        }
    }

    /// Answers one pending form and removes it from the local list so the card
    /// settles immediately, before the tool result arrives.
    func replyForm(_ sessionID: String, formID: String, answer: [String: FormValue]) async throws {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        try await api.replyForm(id: sessionID, formID: formID, answer: answer)
        removeForm(formID, from: sessionID)
    }

    /// Dismisses a pending form. The question tool records the optional message
    /// as its cancellation reason.
    func cancelForm(_ sessionID: String, formID: String, message: String? = nil) async throws {
        guard let api else { throw APIError.transport("Not connected to the hub") }
        try await api.cancelForm(id: sessionID, formID: formID, message: message)
        removeForm(formID, from: sessionID)
    }

    /// The pending form opened by one tool part, if it is still unanswered.
    func pendingForm(sessionID: String, toolPartID: String) -> FormInfo? {
        sessionForms[sessionID]?.forms.first { $0.toolPartID == toolPartID }
    }

    private func removeForm(_ formID: String, from sessionID: String) {
        guard var state = sessionForms[sessionID] else { return }
        state.forms.removeAll { $0.id == formID }
        sessionForms[sessionID] = state
    }
}
