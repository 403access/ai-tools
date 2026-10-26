import SwiftUI

/// Retries a failed turn in the same conversation or in a new forked session.
/// The user can keep the settings OpenCode picked or switch the model/agent
/// before resending.
struct RetryTurnSheet: View {
    @EnvironmentObject private var state: AppState
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
    @State private var showingModelPicker = false
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Retry failed turn")
                        .font(.system(size: 15, weight: .semibold))
                    Text(destination.explanation)
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
                HStack(spacing: 8) {
                    Text("RETRY IN")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)
                    Picker("Retry in", selection: $destination) {
                        ForEach(RetryDestination.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(isWorking)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("PROMPT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if destination == .sameSession, promptText != "continue" {
                        Button("Send “continue”") {
                            prompt = "continue"
                        }
                        .font(.system(size: 9))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                    }
                }
                TextField("Prompt", text: $prompt, axis: .vertical)
                    .font(.system(size: 11))
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .disabled(isWorking)
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
                Button(destination == .newSession ? "Fork & retry" : "Continue") {
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
        .sheet(isPresented: $showingModelPicker) {
            ModelPickerSheet(
                models: models,
                selection: modelChoice,
                variant: selectedVariant
            ) { model, variant in
                modelChoice = model.choice
                selectedVariant = variant
            }
        }
        .onExitCommand { dismiss() }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("MODEL")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if selectedModel != nil {
                        Text("\(models.count) available")
                            .font(.system(size: 8.5))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }

                Button {
                    showingModelPicker = true
                } label: {
                    HStack(spacing: 7) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(modelTitle)
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(modelDetail)
                                .font(.system(size: 8.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking || models.isEmpty)
                .help("Search, filter and pick a model")
            }

            if !selectedVariants.isEmpty {
                HStack(spacing: 6) {
                    Text("VARIANT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .leading)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 64), spacing: 4)],
                        alignment: .leading,
                        spacing: 4
                    ) {
                        ChoiceChip(
                            title: "Default",
                            isSelected: selectedVariant == nil
                        ) {
                            selectedVariant = nil
                        }
                        ForEach(selectedVariants, id: \.id) { variant in
                            ChoiceChip(
                                title: variant.name ?? variant.id,
                                isSelected: selectedVariant == variant.id
                            ) {
                                selectedVariant = variant.id
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("AGENT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 86), spacing: 4)],
                    alignment: .leading,
                    spacing: 4
                ) {
                    ChoiceChip(title: "Keep current", isSelected: selectedAgent == nil) {
                        selectedAgent = nil
                    }
                    if let selectedAgent, !agents.contains(where: { $0.id == selectedAgent }) {
                        ChoiceChip(title: selectedAgent, isSelected: true) {}
                    }
                    ForEach(agents) { agent in
                        ChoiceChip(
                            title: agent.displayName,
                            isSelected: selectedAgent == agent.id
                        ) {
                            selectedAgent = agent.id
                        }
                    }
                }
            }
            .disabled(isWorking)

            Text("OpenCodeBar never changes provider privacy settings or enables training on request data.")
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
        // `.task` runs again if the sheet's content is rebuilt; never clear a
        // catalog or a selection the user has already made.
        guard !catalogsLoaded else { return }
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
            let result = try await state.retryTurn(
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
