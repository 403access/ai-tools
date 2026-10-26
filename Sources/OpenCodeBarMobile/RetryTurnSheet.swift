import SwiftUI

/// Mobile counterpart of the Mac retry sheet: forks before the failed prompt,
/// optionally switches model/agent, then resends the prompt.
struct MobileRetryTurnSheet: View {
    @EnvironmentObject private var store: MobileStore
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

    private var promptText: String { failure.promptText ?? "" }

    private var selectedModel: ModelInfo? {
        guard let modelChoice else { return nil }
        return models.first { $0.choice == modelChoice }
    }

    private var providerIDs: [String] {
        Array(Set(models.map(\.providerID))).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    Text(promptText)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let error = failure.message.error {
                    Section("Failure") {
                        Text(error.type ?? "Turn failed")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.danger)
                        Text(error.displayMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if isLoading {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading OpenCode settings…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section("Model and agent") {
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
                        .pickerStyle(.menu)

                        if let model = selectedModel, let variants = model.variants, !variants.isEmpty {
                            Picker("Variant", selection: $selectedVariant) {
                                Text("Default").tag(String?.none)
                                ForEach(variants, id: \.id) { variant in
                                    Text(variant.name ?? variant.id).tag(Optional(variant.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Picker("Agent", selection: $selectedAgent) {
                            Text("Keep current").tag(String?.none)
                            if let selectedAgent, !agents.contains(where: { $0.id == selectedAgent }) {
                                Text(selectedAgent).tag(Optional(selectedAgent))
                            }
                            ForEach(agents) { agent in
                                Text(agent.displayName).tag(Optional(agent.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Section {
                        Text("The new session keeps the history before this prompt. The original session is unchanged. OpenCodeBar never changes provider privacy settings or enables training on request data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let loadError {
                    Section {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(Theme.warn)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .mobileScreenBackground()
            .navigationTitle("Retry in new session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Retry") {
                        Task { await submit() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isWorking || isLoading || promptText.isEmpty)
                }
            }
            .task { await loadCatalogs() }
            .onChange(of: modelChoice) { _, _ in
                guard let model = selectedModel else { return }
                let variants = model.variants ?? []
                if !variants.contains(where: { $0.id == selectedVariant }) {
                    selectedVariant = nil
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private func loadCatalogs() async {
        isLoading = true
        loadError = nil
        async let modelList = store.modelCatalog(directory: session.directory)
        async let agentList = store.agentCatalog(directory: session.directory)
        do {
            let (allModels, allAgents) = try await (modelList, agentList)
            models = allModels
                .filter(\.isAvailable)
                .sorted { $0.providerID == $1.providerID ? $0.displayName < $1.displayName : $0.providerID < $1.providerID }
            agents = allAgents
                .filter(\.isSelectable)
                .sorted { $0.displayName < $1.displayName }

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
            let forked = try await store.retryTurn(
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
