import SwiftUI

/// Retries a failed turn in a new forked session. The user can keep the
/// settings OpenCode picked or switch the model/agent before resending.
struct RetryTurnSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let session: Session
    let failure: FailedTurn
    let onForked: (Session) -> Void

    @State private var models: [ModelInfo] = []
    @State private var agents: [AgentInfo] = []
    @State private var modelChoice: ModelChoice?
    @State private var selectedVariant: String?
    @State private var selectedAgent: String?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(session: Session, failure: FailedTurn, onForked: @escaping (Session) -> Void) {
        self.session = session
        self.failure = failure
        self.onForked = onForked
        if let model = failure.model {
            _modelChoice = State(initialValue: ModelChoice(model))
            _selectedVariant = State(initialValue: model.variant)
        }
        _selectedAgent = State(initialValue: failure.agent)
    }

    private var promptText: String {
        failure.promptText ?? ""
    }

    private var selectedModel: ModelInfo? {
        guard let modelChoice else { return nil }
        return models.first { $0.choice == modelChoice }
    }

    private var providerIDs: [String] {
        Array(Set(models.map(\.providerID))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retry in a new session")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Fork this conversation before the failed prompt, then send it again.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .disabled(isWorking)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("PROMPT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text(promptText)
                    .font(.system(size: 11))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
            }

            if let error = failure.message.error {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.type ?? "Turn failed")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.danger)
                    Text(error.displayMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.danger.opacity(0.08))
                )
            }

            if isLoading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Loading OpenCode models and agents…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else {
                settingsSection
            }

            if let loadError {
                Text(loadError)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button("Retry") {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isWorking || promptText.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
        .task { await loadCatalogs() }
        .onExitCommand { dismiss() }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("MODEL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)

                Picker("Model", selection: $modelChoice) {
                    ForEach(providerIDs, id: \.self) { provider in
                        Section(provider) {
                            ForEach(models.filter { $0.providerID == provider }, id: \.choice) { model in
                                Text("\(model.displayName) · \(model.providerID)")
                                    .tag(Optional(model.choice))
                            }
                        }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(isWorking)
            }

            if let model = selectedModel, let variants = model.variants, !variants.isEmpty {
                HStack(spacing: 8) {
                    Text("VARIANT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)

                    Picker("Variant", selection: $selectedVariant) {
                        Text("Default").tag(String?.none)
                        ForEach(variants, id: \.id) { variant in
                            Text(variant.name ?? variant.id).tag(Optional(variant.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(isWorking)
                }
            }

            HStack(spacing: 8) {
                Text("AGENT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .leading)

                Picker("Agent", selection: $selectedAgent) {
                    Text("Keep current").tag(String?.none)
                    if let selectedAgent, !agents.contains(where: { $0.id == selectedAgent }) {
                        Text(selectedAgent).tag(Optional(selectedAgent))
                    }
                    ForEach(agents) { agent in
                        Text(agent.displayName).tag(Optional(agent.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(isWorking)
            }

            Text("The new session keeps the history before this prompt. The original session is unchanged. OpenCodeBar never changes provider privacy settings or enables training on request data.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: modelChoice) { _, _ in
            guard let model = selectedModel else { return }
            let variants = model.variants ?? []
            if !variants.contains(where: { $0.id == selectedVariant }) {
                selectedVariant = nil
            }
        }
    }

    private func loadCatalogs() async {
        isLoading = true
        loadError = nil
        async let modelList = state.modelCatalog(directory: session.directory)
        async let agentList = state.agentCatalog(directory: session.directory)
        do {
            let (allModels, allAgents) = try await (modelList, agentList)
            models = allModels
                .filter(\.isAvailable)
                .sorted { $0.providerID == $1.providerID ? $0.displayName < $1.displayName : $0.providerID < $1.providerID }
            agents = allAgents
                .filter(\.isSelectable)
                .sorted { $0.displayName < $1.displayName }

            // Keep the failed turn's model visible even if it is no longer in
            // the catalog, so the picker does not silently jump elsewhere.
            if let current = failure.model,
               !models.contains(where: { $0.choice == ModelChoice(current) }) {
                models.insert(
                    ModelInfo(
                        id: current.id,
                        modelID: current.id,
                        providerID: current.providerID,
                        name: current.label,
                        enabled: true,
                        status: "active",
                        variants: nil
                    ),
                    at: 0
                )
            }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func submit() async {
        guard !isWorking, !promptText.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let model = selectedModel?.ref(variant: selectedVariant) ?? failure.model
            let forked = try await state.retryTurn(
                from: session,
                before: failure.prompt.id,
                prompt: promptText,
                model: model,
                agent: selectedAgent
            )
            onForked(forked)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
