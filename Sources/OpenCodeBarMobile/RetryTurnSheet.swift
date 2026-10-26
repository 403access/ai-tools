import SwiftUI

/// Mobile counterpart of the Mac retry sheet: resends the prompt in this
/// conversation or forks before the failed prompt, optionally switching
/// model/agent first.
struct MobileRetryTurnSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let session: Session
    let failure: FailedTurn
    /// Called only when a new fork was created, so the app can open it.
    let onForked: (Session) -> Void

    @State private var destination: RetryDestination = .sameSession
    @State private var prompt: String
    @State private var models: [ModelInfo] = []
    @State private var agents: [AgentInfo] = []
    @State private var modelChoice: ModelChoice?
    @State private var selectedVariant: String?
    @State private var selectedAgent: String?
    @State private var isLoading = true
    @State private var catalogsLoaded = false
    @State private var loadError: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

    init(session: Session, failure: FailedTurn, onForked: @escaping (Session) -> Void) {
        self.session = session
        self.failure = failure
        self.onForked = onForked
        _prompt = State(initialValue: failure.promptText ?? "")
        if let model = failure.model {
            _modelChoice = State(initialValue: ModelChoice(model))
            _selectedVariant = State(initialValue: model.variant)
        }
        _selectedAgent = State(initialValue: failure.agent)
    }

    private var promptText: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedModel: ModelInfo? {
        guard let modelChoice else { return nil }
        return models.first { $0.choice == modelChoice }
    }

    private var selectedVariants: [ModelInfo.Variant] {
        selectedModel?.variants ?? []
    }

    private var modelTitle: String {
        selectedModel?.displayName ?? failure.model?.label ?? "Choose a model"
    }

    private var modelDetail: String {
        guard let selectedModel else {
            return failure.model?.providerID ?? "The failed turn's model"
        }
        let variantName = selectedVariants
            .first { $0.id == selectedVariant }
            .map { $0.name ?? $0.id }
        let provider = selectedModel.providerID
        if let variantName {
            return "\(provider) · \(variantName)"
        }
        return "\(provider) · default variant"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Retry in", selection: $destination) {
                        ForEach(RetryDestination.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(destination.explanation)
                }

                Section("Prompt") {
                    TextField("Prompt", text: $prompt, axis: .vertical)
                        .font(.subheadline)
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.sentences)

                    if destination == .sameSession, promptText != "continue" {
                        Button("Send “continue” instead") {
                            prompt = "continue"
                        }
                        .font(.footnote)
                    }
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
                        modelLink

                        if !selectedVariants.isEmpty {
                            variantChoices
                        }

                        agentChoices
                    }

                    Section {
                        Text("OpenCodeBar never changes provider privacy settings or enables training on request data.")
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
            .navigationTitle("Retry failed turn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(destination == .newSession ? "Fork & retry" : "Continue") {
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

    // MARK: - Settings

    private var modelLink: some View {
        NavigationLink {
            MobileModelPickerView(
                models: models,
                selection: modelChoice,
                variant: selectedVariant
            ) { model, variant in
                modelChoice = model.choice
                selectedVariant = variant
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(modelTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(modelDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            .padding(.vertical, 2)
        }
        .disabled(models.isEmpty)
    }

    private var variantChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Variant")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 84), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ChoiceChip(
                    title: "Default",
                    isSelected: selectedVariant == nil,
                    fontSize: 13
                ) {
                    selectedVariant = nil
                }
                ForEach(selectedVariants, id: \.id) { variant in
                    ChoiceChip(
                        title: variant.name ?? variant.id,
                        isSelected: selectedVariant == variant.id,
                        fontSize: 13
                    ) {
                        selectedVariant = variant.id
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var agentChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ChoiceChip(title: "Keep current", isSelected: selectedAgent == nil, fontSize: 13) {
                    selectedAgent = nil
                }
                if let selectedAgent, !agents.contains(where: { $0.id == selectedAgent }) {
                    ChoiceChip(title: selectedAgent, isSelected: true, fontSize: 13) {}
                }
                ForEach(agents) { agent in
                    ChoiceChip(
                        title: agent.displayName,
                        isSelected: selectedAgent == agent.id,
                        fontSize: 13
                    ) {
                        selectedAgent = agent.id
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Data

    private func loadCatalogs() async {
        // Never clear a catalog the user has already started choosing from.
        guard !catalogsLoaded else { return }
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
            catalogsLoaded = true
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
            let result = try await store.retryTurn(
                from: session,
                before: failure.prompt.id,
                prompt: promptText,
                model: model,
                agent: selectedAgent,
                destination: destination
            )
            if destination == .newSession { onForked(result) }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
