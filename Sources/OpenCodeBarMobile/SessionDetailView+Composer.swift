import PhotosUI
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
                    LazyVStack(alignment: .leading, spacing: 5) {
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
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
            && !isSending
            && !isSwitchingModel
    }

    var composer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let sendError {
                Text(sendError)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            modelControl

            PromptAttachmentStrip(attachments: $attachments, disabled: isSending)

            HStack(alignment: .center, spacing: 8) {
                PhotosPicker(
                    selection: $photoSelection,
                    maxSelectionCount: 8,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 19))
                        .foregroundStyle(isSending ? Color.secondary.opacity(0.45) : Theme.accent)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .accessibilityLabel("Attach images")
                .onChange(of: photoSelection) { _, items in
                    Task { await loadSelectedPhotos(items) }
                }

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

    /// Compact model selector for the next turn. Choosing a model switches the
    /// session, so the message about to be sent (or queued) uses it.
    var modelControl: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await loadModelsIfNeeded()
                    if !models.isEmpty { showingModelPicker = true }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .font(.system(size: 10, weight: .semibold))
                    Text(currentModelLabel)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if isLoadingModels || isSwitchingModel {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                .overlay(
                    Capsule().strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isSending || isLoadingModels || isSwitchingModel)
            .accessibilityLabel("Change model")
            .accessibilityValue(currentModelLabel)

            if let modelError {
                Text(modelError)
                    .font(.caption2)
                    .foregroundStyle(Theme.danger)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    /// Applies the picked model to the session before the next prompt.
    func selectModel(_ model: ModelInfo, variant: String?) async {
        guard !isSwitchingModel else { return }
        isSwitchingModel = true
        modelError = nil
        do {
            let ref = model.ref(variant: variant)
            try await store.switchModel(id: sessionID, model: ref)
            modelOverride = ref
            defaultModelInfo = model
        } catch {
            modelError = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
        isSwitchingModel = false
    }

    func send() async {
        dictation.cancel()
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments.map { $0.toInput() }
        guard (!text.isEmpty || !files.isEmpty), !isSending, !isSwitchingModel else { return }

        isSending = true
        sendError = nil
        do {
            try await store.promptSession(
                id: sessionID,
                text: text,
                delivery: isRunning ? .queue : nil,
                files: files.isEmpty ? nil : files
            )
            draft = ""
            attachments.removeAll()
            photoSelection.removeAll()
            await loadLatest()
            scrollRequest += 1
        } catch {
            sendError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isSending = false
    }

    func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let attachment = await PromptDraftAttachment.load(from: item) {
                attachments.append(attachment)
            }
        }
        photoSelection.removeAll()
    }
}
