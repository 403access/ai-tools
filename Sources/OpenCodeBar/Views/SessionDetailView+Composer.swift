import SwiftUI

extension SessionDetailView {
    // MARK: - Pending queue

    @ViewBuilder
    var pendingQueue: some View {
        let pending = state.sessionPending[session.id]
        if let items = pending?.items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.badge")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Queued · \(items.count)")
                        .font(.system(size: 9, weight: .bold))
                    Spacer()
                    if pending?.isLoading == true {
                        ProgressView().controlSize(.mini)
                    }
                }
                .foregroundStyle(Theme.accent)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { item in
                            pendingRow(item)
                        }
                    }
                }
                .frame(maxHeight: 110)

                if let pendingError {
                    Text(pendingError)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 8)
        }
    }

    func pendingRow(_ item: SessionPending) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(item.promptText ?? "Queued prompt")
                .font(.system(size: 10))
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.delivery == .steer {
                Chip(text: item.deliveryLabel, tint: Theme.reasoning)
            }

            if cancellingPending.contains(item.id) {
                ProgressView().controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                Button {
                    Task { await cancelPending(item) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Remove this queued prompt")
                .accessibilityLabel("Remove queued prompt")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    func cancelPending(_ item: SessionPending) async {
        guard !cancellingPending.contains(item.id) else { return }
        cancellingPending.insert(item.id)
        pendingError = nil
        defer { cancellingPending.remove(item.id) }
        do {
            try await state.cancelPending(session.id, itemID: item.id)
        } catch {
            pendingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Composer

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sendError {
                Text(sendError)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 6) {
                TextField(
                    isRunning ? "Queue a message…" : "Message this session…",
                    text: $draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .lineLimit(1...4)
                .focused($composerFocused)
                .onSubmit { Task { await send() } }

                VoiceInputButton(dictation: dictation, text: $draft, iconSize: 13)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(canSend ? Theme.accent : Color.secondary.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 21, height: 21)
                .contentShape(Rectangle())
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send prompt (⌘Return)")
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        composerFocused ? Theme.accent.opacity(0.45) : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
    }

    func send() async {
        dictation.cancel()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        isSending = true
        sendError = nil
        do {
            // A running session queues the message instead of interrupting the
            // current turn.
            try await state.promptSession(
                id: session.id,
                text: text,
                delivery: isRunning ? .queue : nil
            )
            draft = ""
            await loadLatest()
            scrollRequest += 1
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }
}
