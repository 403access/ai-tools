import PhotosUI
import SwiftUI

/// Mobile counterpart of the Mac New Session sheet. Creates a session in a
/// project directory and can send the first prompt in the same flow.
struct MobileNewSessionSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Session) -> Void

    private enum Source: String, CaseIterable, Identifiable {
        case existing
        case clone

        var id: String { rawValue }
        var label: String { self == .existing ? "Existing" : "Clone" }
    }

    private enum Workspace: String, CaseIterable, Identifiable {
        case folder
        case worktree

        var id: String { rawValue }
        var label: String { self == .folder ? "Current folder" : "Worktree" }
    }

    private enum StartMode: String, CaseIterable, Identifiable {
        case now
        case in15
        case in60
        case custom

        var id: String { rawValue }
        var label: String {
            switch self {
            case .now: return "Now"
            case .in15: return "15m"
            case .in60: return "1h"
            case .custom: return "Time"
            }
        }
    }

    @State private var directory: String
    @State private var title = ""
    @State private var prompt = ""
    @State private var attachments: [PromptDraftAttachment] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var startMode: StartMode = .now
    @State private var customStart = Date().addingTimeInterval(60 * 60)
    @State private var source: Source = .existing
    @State private var workspace: Workspace = .folder
    @State private var repositoryURL = ""
    @State private var parentDirectory = ""
    @State private var folderName = ""
    @State private var clonedRepository: ClonedRepository?
    @State private var createdWorktree: CreatedWorktree?
    @State private var isCloning = false
    @State private var isCreatingWorktree = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var createdSession: Session?
    @State private var models: [ModelInfo] = []
    @State private var agents: [AgentInfo] = []
    @State private var modelChoice: ModelChoice?
    @State private var selectedVariant: String?
    @State private var selectedAgent: String?
    @State private var catalogsLoading = false
    @State private var catalogError: String?
    @State private var loadedCatalogDirectory: String?
    @StateObject private var dictation = SpeechDictation()
    @FocusState private var promptFocused: Bool

    init(directory: String? = nil, onCreated: @escaping (Session) -> Void = { _ in }) {
        _directory = State(initialValue: directory ?? "")
        self.onCreated = onCreated
    }

    private var trimmedDirectory: String {
        directory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedRepositoryURL: String {
        repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedParentDirectory: String {
        parentDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFolderName: String {
        folderName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedProject: Project? {
        store.orderedProjects.first { $0.canonical == trimmedDirectory }
    }

    private var selectedRunningCount: Int {
        selectedProject.map { store.runningSessions(in: $0).count } ?? 0
    }

    private var canUseWorktree: Bool {
        selectedProject?.vcs == "git"
    }

    private var workspaceHint: String {
        if !canUseWorktree {
            return "Worktrees need a known Git project."
        }
        if workspace == .worktree {
            return "Creates a fresh checkout so this session's changes stay out of the current folder."
        }
        return "Changes are written directly in this folder."
    }

    private var canSubmit: Bool {
        guard !isWorking else { return false }
        if scheduledStart != nil, trimmedPrompt.isEmpty, attachments.isEmpty { return false }
        switch source {
        case .existing:
            guard !trimmedDirectory.isEmpty else { return false }
            return workspace == .folder || canUseWorktree
        case .clone:
            return !trimmedRepositoryURL.isEmpty && !trimmedParentDirectory.isEmpty
        }
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Non-nil when the first message should wait for a later start time. The
    /// hub still queues it behind the concurrency limit when that is reached.
    /// Image attachments are sent immediately; scheduling is ignored when
    /// images are attached.
    private var scheduledStart: Date? {
        guard attachments.isEmpty else { return nil }
        switch startMode {
        case .now: return nil
        case .in15: return Date().addingTimeInterval(15 * 60)
        case .in60: return Date().addingTimeInterval(60 * 60)
        case .custom: return max(customStart, Date().addingTimeInterval(60))
        }
    }

    private var startHint: String {
        if !attachments.isEmpty {
            return "The first message and images are sent immediately after the session is created."
        }
        guard let scheduledStart else {
            return "Starts immediately unless the hub is already running its maximum number of agents."
        }
        return "Queued \(SessionControlFormat.relative(scheduledStart)); starts sooner if a slot frees."
    }

    private var actionTitle: String {
        if createdSession != nil { return "Send" }
        if source == .clone && clonedRepository == nil { return "Clone & start" }
        if source == .existing && workspace == .worktree && createdWorktree == nil {
            return "Worktree & start"
        }
        return "Start"
    }

    private var progressLabel: String {
        if isCloning { return "Cloning repository…" }
        if isCreatingWorktree { return "Creating worktree…" }
        return createdSession == nil ? "Creating session…" : "Sending…"
    }

    private var cloneDestinationHint: String {
        guard !trimmedParentDirectory.isEmpty else { return "" }
        let name = trimmedFolderName.isEmpty ? "repository" : trimmedFolderName
        return (trimmedParentDirectory as NSString).appendingPathComponent(name)
    }

    private var catalogDirectory: String {
        switch source {
        case .existing:
            return trimmedDirectory
        case .clone:
            return trimmedParentDirectory
        }
    }

    private var selectedModel: ModelInfo? {
        guard let modelChoice else { return nil }
        return models.first { $0.choice == modelChoice }
    }

    private var selectedVariants: [ModelInfo.Variant] {
        selectedModel?.variants ?? []
    }

    private var selectedModelRef: ModelRef? {
        selectedModel?.ref(variant: selectedVariant)
    }

    private var modelTitle: String {
        selectedModel?.displayName ?? "OpenCode default"
    }

    private var modelDetail: String {
        guard let selectedModel else {
            return "Uses the default model for this directory"
        }
        let variantName = selectedVariants
            .first { $0.id == selectedVariant }
            .map { $0.name ?? $0.id }
        if let variantName {
            return "\(selectedModel.providerID) · \(variantName)"
        }
        return "\(selectedModel.providerID) · default variant"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        createdSession == nil
                            ? (source == .clone
                                ? "Clone a repository on your Mac, then start a session in it."
                                : "Pick a project and say what you need. OpenCode starts in that folder.")
                            : "Session created. Retry the message, or close this sheet and write it in the conversation."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    projectSection
                    modelAgentSection
                    titleSection
                    messageSection
                    startSection

                    if let errorMessage {
                        NoticeRow(
                            icon: "exclamationmark.triangle.fill",
                            message: errorMessage,
                            tint: Theme.warn
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .mobileScreenBackground()
            .navigationTitle("New session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        Task { await submit() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(progressLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if trimmedDirectory.isEmpty {
                directory = store.orderedProjects.first?.canonical ?? ""
            }
            if trimmedParentDirectory.isEmpty {
                parentDirectory = defaultParentDirectory
            }
            store.loadProjectIcons(for: store.orderedProjects)
            promptFocused = true
        }
        .task(id: catalogDirectory) {
            await loadCatalogs()
        }
        .onChange(of: source) { _, _ in
            clonedRepository = nil
            createdWorktree = nil
            workspace = .folder
        }
        .onChange(of: workspace) { _, _ in createdWorktree = nil }
        .onChange(of: trimmedDirectory) { _, _ in
            createdWorktree = nil
            if workspace == .worktree && !canUseWorktree {
                workspace = .folder
            }
        }
        .onChange(of: repositoryURL) { _, _ in clonedRepository = nil }
        .onChange(of: parentDirectory) { _, _ in clonedRepository = nil }
        .onChange(of: folderName) { _, _ in clonedRepository = nil }
        .onDisappear {
            dictation.cancel()
            attachments.removeAll()
            photoSelection.removeAll()
        }
    }

    private var defaultParentDirectory: String {
        let seed = trimmedDirectory.isEmpty
            ? store.orderedProjects.first?.canonical ?? ""
            : trimmedDirectory
        guard !seed.isEmpty else { return "~/Developer" }
        let parent = (seed as NSString).deletingLastPathComponent
        return parent.isEmpty ? "~/Developer" : parent
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader(source == .existing ? "Project" : "Repository") {
                if source == .existing, let selectedProject {
                    Chip(text: selectedProject.vcs ?? "folder", tint: Theme.accent)
                }
            }

            if createdSession == nil {
                Picker("Project source", selection: $source) {
                    ForEach(Source.allCases) { source in
                        Text(source.label).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isWorking)
            }

            if source == .existing {
                if !store.orderedProjects.isEmpty {
                    NavigationLink {
                        MobileProjectPickerView(
                            selectedDirectory: trimmedDirectory,
                            onSelect: { directory = $0.canonical }
                        )
                    } label: {
                        HStack(spacing: 11) {
                            ProjectIconTile(
                                image: selectedProject.flatMap { store.projectIcons[$0.id] },
                                running: selectedRunningCount > 0,
                                size: 32
                            )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(
                                    selectedProject?.displayName
                                        ?? (trimmedDirectory.isEmpty ? "Choose a project" : "Custom directory")
                                )
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                                Text(shortPath)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 4)

                            if selectedRunningCount > 0 {
                                HStack(spacing: 3) {
                                    PulsingDot(size: 4)
                                    Text("\(selectedRunningCount)")
                                        .font(.caption2.weight(.bold))
                                        .monospacedDigit()
                                }
                                .foregroundStyle(Theme.running)
                            }

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(11)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(MobileTheme.field)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(MobileTheme.border, lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(createdSession != nil)
                    .accessibilityLabel("Choose a project")
                    .accessibilityValue(selectedProject?.displayName ?? "Custom directory")
                    .accessibilityHint("Opens the searchable project browser")
                }

                TextField("Project directory", text: $directory)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(createdSession != nil)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(fieldBackground)
                    .overlay(fieldBorder)

                Text(shortPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                VStack(alignment: .leading, spacing: 7) {
                    SectionHeader("Workspace")

                    Picker("Workspace", selection: $workspace) {
                        ForEach(Workspace.allCases) { workspace in
                            Text(workspace.label).tag(workspace)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isWorking || createdSession != nil || !canUseWorktree)

                    Text(workspaceHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            } else {
                Text("Repository URL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("https://github.com/owner/repo", text: $repositoryURL)
                    .font(.footnote.monospaced())
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isWorking || createdSession != nil)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(fieldBackground)
                    .overlay(fieldBorder)

                Text("Clone into")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                TextField("Parent folder, e.g. ~/Developer", text: $parentDirectory)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isWorking || createdSession != nil)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(fieldBackground)
                    .overlay(fieldBorder)

                Text("Folder name · optional")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                TextField("Use the repository name", text: $folderName)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(isWorking || createdSession != nil)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(fieldBackground)
                    .overlay(fieldBorder)

                if !cloneDestinationHint.isEmpty {
                    Text(cloneDestinationHint)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(MobileTheme.field)
    }

    private var fieldBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(MobileTheme.border, lineWidth: 1)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Title · optional")
            TextField("Let OpenCode name it from the first message", text: $title)
                .font(.subheadline)
                .disabled(createdSession != nil)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MobileTheme.field)
                )
        }
    }

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("First message · optional")

            PromptAttachmentStrip(attachments: $attachments, disabled: isWorking)

            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(
                    selection: $photoSelection,
                    maxSelectionCount: 8,
                    matching: .images
                ) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 18))
                        .foregroundStyle(isWorking ? Color.secondary.opacity(0.45) : Theme.accent)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
                .accessibilityLabel("Attach images")
                .onChange(of: photoSelection) { _, items in
                    Task { await loadSelectedPhotos(items) }
                }

                TextField("What should OpenCode do?", text: $prompt, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(4...8)
                    .focused($promptFocused)
                    .submitLabel(.return)
                    .disabled(isWorking)

                VoiceInputButton(dictation: dictation, text: $prompt, iconSize: 18)
                    .disabled(isWorking)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(MobileTheme.field)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        promptFocused ? Theme.accent.opacity(0.5) : MobileTheme.border,
                        lineWidth: 1
                    )
            )
        }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Start")

            Picker("Start", selection: $startMode) {
                ForEach(StartMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(isWorking || !attachments.isEmpty)

            if startMode == .custom && attachments.isEmpty {
                DatePicker(
                    "Start at",
                    selection: $customStart,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            }

            Text(startHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortPath: String {
        trimmedDirectory.isEmpty
            ? "Choose a folder on your Mac"
            : (trimmedDirectory as NSString).abbreviatingWithTildeInPath
    }

    private var modelAgentSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Model and agent · optional")

            if catalogsLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading OpenCode settings…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            } else if catalogDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Choose a project or folder to load available models and agents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
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
                        if modelChoice != nil {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.accent)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(11)
                    .background(fieldBackground)
                    .overlay(fieldBorder)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(models.isEmpty)
                .accessibilityLabel("Choose a model")

                if !selectedVariants.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Variant")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ChoiceChip(
                                    title: "Default",
                                    isSelected: selectedVariant == nil,
                                    fontSize: 12
                                ) {
                                    selectedVariant = nil
                                }
                                ForEach(selectedVariants, id: \.id) { variant in
                                    ChoiceChip(
                                        title: variant.name ?? variant.id,
                                        isSelected: selectedVariant == variant.id,
                                        fontSize: 12
                                    ) {
                                        selectedVariant = variant.id
                                    }
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Agent")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 6)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        ChoiceChip(title: "Default", isSelected: selectedAgent == nil, fontSize: 12) {
                            selectedAgent = nil
                        }
                        if let selectedAgent, !agents.contains(where: { $0.id == selectedAgent }) {
                            ChoiceChip(title: selectedAgent, isSelected: true, fontSize: 12) {}
                        }
                        ForEach(agents) { agent in
                            ChoiceChip(
                                title: agent.displayName,
                                isSelected: selectedAgent == agent.id,
                                fontSize: 12
                            ) {
                                selectedAgent = agent.id
                            }
                        }
                    }
                }

                if let catalogError {
                    Text(catalogError)
                        .font(.caption2)
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("OpenCodeBar never changes provider privacy settings or enables training on request data.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: modelChoice) { _, _ in
            guard let model = selectedModel else { return }
            let variants = model.variants ?? []
            if !variants.contains(where: { $0.id == selectedVariant }) {
                selectedVariant = nil
            }
        }
    }

    private func resolveSessionDirectory() async throws -> String {
        guard createdSession == nil, source == .existing, workspace == .worktree else {
            return trimmedDirectory
        }
        guard let project = selectedProject, project.vcs == "git" else {
            throw MobileNewSessionError.worktreeRequiresGitProject
        }
        if let createdWorktree {
            return createdWorktree.directory
        }

        isCreatingWorktree = true
        let worktree = try await store.createWorktree(projectID: project.id)
        createdWorktree = worktree
        isCreatingWorktree = false
        return worktree.directory
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            if let attachment = await PromptDraftAttachment.load(from: item) {
                attachments.append(attachment)
            }
        }
        photoSelection.removeAll()
    }

    private func submit() async {
        dictation.cancel()
        guard canSubmit else { return }

        isWorking = true
        errorMessage = nil
        defer { isCreatingWorktree = false }
        do {
            if source == .clone {
                if let clonedRepository {
                    directory = clonedRepository.directory
                } else {
                    isCloning = true
                    let cloned = try await store.cloneRepository(
                        url: trimmedRepositoryURL,
                        parent: trimmedParentDirectory,
                        name: trimmedFolderName
                    )
                    isCloning = false
                    clonedRepository = cloned
                    directory = cloned.directory
                }
            }

            let sessionDirectory = try await resolveSessionDirectory()
            let session: Session
            if let createdSession {
                session = createdSession
            } else {
                session = try await store.createSession(
                    title: title,
                    directory: sessionDirectory
                )
                createdSession = session
            }

            if let model = selectedModelRef {
                try await store.switchModel(id: session.id, model: model)
            }
            if let agent = selectedAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !agent.isEmpty {
                try await store.switchAgent(id: session.id, agent: agent)
            }

            let message = trimmedPrompt
            let files = attachments.map { $0.toInput() }
            if !message.isEmpty || !files.isEmpty {
                try await store.promptSession(
                    id: session.id,
                    text: message,
                    startAt: scheduledStart,
                    files: files.isEmpty ? nil : files
                )
            }

            onCreated(session)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isCloning = false
        isWorking = false
    }

    private func loadCatalogs() async {
        let dir = catalogDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else {
            models = []
            agents = []
            catalogError = nil
            loadedCatalogDirectory = nil
            return
        }
        if loadedCatalogDirectory == dir && (!models.isEmpty || !agents.isEmpty) {
            return
        }

        catalogsLoading = true
        catalogError = nil
        async let modelList = store.modelCatalog(directory: dir)
        async let agentList = store.agentCatalog(directory: dir)
        do {
            let (allModels, allAgents) = try await (modelList, agentList)
            models = allModels
                .filter(\.isAvailable)
                .sorted { $0.providerID == $1.providerID ? $0.displayName < $1.displayName : $0.providerID < $1.providerID }
            agents = allAgents
                .filter(\.isSelectable)
                .sorted { $0.displayName < $1.displayName }

            if let modelChoice, !models.contains(where: { $0.choice == modelChoice }) {
                self.modelChoice = nil
                selectedVariant = nil
            } else if let model = selectedModel {
                let variants = model.variants ?? []
                if !variants.contains(where: { $0.id == selectedVariant }) {
                    selectedVariant = nil
                }
            }
            if let selectedAgent, !agents.contains(where: { $0.id == selectedAgent }) {
                self.selectedAgent = nil
            }
            loadedCatalogDirectory = dir
        } catch {
            catalogError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        catalogsLoading = false
    }
}

private enum MobileNewSessionError: LocalizedError {
    case worktreeRequiresGitProject

    var errorDescription: String? {
        switch self {
        case .worktreeRequiresGitProject:
            return "Select a known Git project to create a worktree."
        }
    }
}
