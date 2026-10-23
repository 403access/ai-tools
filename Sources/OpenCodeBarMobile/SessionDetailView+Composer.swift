import SwiftUI

extension SessionDetailView {
    // MARK: - Pending queue

    @ViewBuilder
    var pendingQueue: some View {
        let pending = store.sessionPending[sessionID]
        if let items = pending?.items, !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "clock.badge")
                        .font(.caption2.weight(.semibold))
                    Text("Queued · \(items.count)")
                        .font(.caption2.weight(.bold))
                    Spacer()
                    if pending?.isLoading == true {
                        ProgressView().controlSize(.mini)
                    }
                }
                .foregroundStyle(Theme.accent)

                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(items) { item in
                            pendingRow(item)
                        }
                    }
                }
                .frame(maxHeight: 132)

                if let pendingError {
                    Text(pendingError)
                        .font(.caption2)
                        .foregroundStyle(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
        }
    }

    func pendingRow(_ item: SessionPending) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(item.promptText ?? "Queued prompt")
                .font(.caption)
                .lineLimit(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if item.delivery == .steer {
                Chip(text: item.deliveryLabel, tint: Theme.reasoning)
            }

            if cancellingPending.contains(item.id) {
                ProgressView().controlSize(.mini)
                    .frame(width: 18, height: 18)
            } else {
                Button {
                    Task { await cancelPending(item) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove queued prompt")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(MobileTheme.field)
        )
    }

    func cancelPending(_ item: SessionPending) async {
        guard !cancellingPending.contains(item.id) else { return }
        cancellingPending.insert(item.id)
        pendingError = nil
        defer { cancellingPending.remove(item.id) }
        do {
            try await store.cancelPending(sessionID, itemID: item.id)
        } catch {
            pendingError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Composer

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let sendError {
                Text(sendError)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .center, spacing: 8) {
                TextField(
                    isRunning ? "Queue a message…" : "Message this session…",
                    text: $draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.subheadline)
                .lineLimit(1...5)
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { Task { await send() } }

                VoiceInputButton(dictation: dictation, text: $draft, iconSize: 19)

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(canSend ? Theme.accent : Color.secondary.opacity(0.45))
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(MobileTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        composerFocused ? Theme.accent.opacity(0.5) : MobileTheme.border,
                        lineWidth: 1
                    )
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    func send() async {
        dictation.cancel()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        isSending = true
        sendError = nil
        do {
            try await store.promptSession(
                id: sessionID,
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
