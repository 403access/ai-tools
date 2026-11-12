import SwiftUI

/// Starts a new OpenCode session in a project directory, optionally with a
/// first prompt. Opened from the tasks board or a project's detail page.
struct NewSessionSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable, Identifiable {
        case existing
        case clone

        var id: String { rawValue }
        var label: String { self == .existing ? "Existing folder" : "Clone repository" }
    }

    private enum Workspace: String, CaseIterable, Identifiable {
        case folder
        case worktree

        var id: String { rawValue }
        var label: String { self == .folder ? "Current folder" : "Git worktree" }
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
    @State private var startMode: StartMode = .now
    @State private var customStart = Date().addingTimeInterval(60 * 60)
    @State private var source: Source = .existing
    @State private var workspace: Workspace = .folder
    @State private var repositoryURL = ""
    @State private var parentDirectory = ""
    @State private var folderName = ""
    @State private var clonedRepository: ClonedRepository?
    @State private var createdWorktree: CreatedWorktree?
    @State private var isWorking = false
    @State private var isCreatingWorktree = false
    @State private var errorMessage: String?
    @State private var createdSession: Session?
    @State private var showingProjectPicker = false
    @State private var showingGitHubPicker = false
    @State private var showingModelPicker = false
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

    #if DEBUG
    /// State used by the offscreen sheet gallery. Raw strings keep the private
    /// picker enums out of the preview API.
    struct PreviewState {
        var directory: String = "/Users/olivermolnar/Developer/ai-tools"
        var title = ""
        var prompt = ""
        var startMode = "now"
        var customStart = Date().addingTimeInterval(60 * 60)
        var source = "existing"
        var workspace = "folder"
        var repositoryURL = ""
        var parentDirectory = "~/Developer"
        var folderName = ""
        var models: [ModelInfo] = []
        var agents: [AgentInfo] = []
        var modelChoice: ModelChoice?
        var selectedVariant: String?
        var selectedAgent: String?
        var catalogsLoading = false
        var catalogError: String?
        var createdSession: Session?
        var errorMessage: String?
        var isWorking = false
        var catalogsProvided = true
    }

    private var previewCatalogsProvided = false
    #endif

    init(directory: String? = nil) {
        _directory = State(initialValue: directory ?? "")
    }

    #if DEBUG
    init(preview: PreviewState) {
        self.previewCatalogsProvided = preview.catalogsProvided
        _directory = State(initialValue: preview.directory)
        _title = State(initialValue: preview.title)
        _prompt = State(initialValue: preview.prompt)
        _startMode = State(initialValue: StartMode(rawValue: preview.startMode) ?? .now)
        _customStart = State(initialValue: preview.customStart)
        _source = State(initialValue: Source(rawValue: preview.source) ?? .existing)
        _workspace = State(initialValue: Workspace(rawValue: preview.workspace) ?? .folder)
        _repositoryURL = State(initialValue: preview.repositoryURL)
        _parentDirectory = State(initialValue: preview.parentDirectory)
        _folderName = State(initialValue: preview.folderName)
        _models = State(initialValue: preview.models)
        _agents = State(initialValue: preview.agents)
        _modelChoice = State(initialValue: preview.modelChoice)
        _selectedVariant = State(initialValue: preview.selectedVariant)
        _selectedAgent = State(initialValue: preview.selectedAgent)
        _catalogsLoading = State(initialValue: preview.catalogsLoading)
        _catalogError = State(initialValue: preview.catalogError)
        _createdSession = State(initialValue: preview.createdSession)
        _errorMessage = State(initialValue: preview.errorMessage)
        _isWorking = State(initialValue: preview.isWorking)
    }
    #endif

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
        state.orderedProjects.first(where: { $0.canonical == trimmedDirectory })
    }

    private var selectedRunningCount: Int {
        selectedProject.map { state.runningSessions(in: $0).count } ?? 0
    }

    private var runningCounts: [String: Int] {
        state.runningByProject.mapValues(\.count)
    }

    private var shortDirectory: String {
        let path = (trimmedDirectory as NSString).abbreviatingWithTildeInPath
        return path.isEmpty ? "No folder selected" : path
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
        if scheduledStart != nil, trimmedPrompt.isEmpty { return false }
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
    private var scheduledStart: Date? {
        switch startMode {
        case .now: return nil
        case .in15: return Date().addingTimeInterval(15 * 60)
        case .in60: return Date().addingTimeInterval(60 * 60)
        case .custom: return max(customStart, Date().addingTimeInterval(60))
        }
    }

    private var startHint: String {
        guard let scheduledStart else {
            return "The first message starts immediately unless the hub is already running its maximum number of agents."
        }
        return "Queued to start \(SessionControlFormat.relative(scheduledStart)). It starts sooner if a slot frees."
    }

    private var actionTitle: String {
        if createdSession != nil { return "Send message" }
        if source == .clone && clonedRepository == nil { return "Clone & create" }
        if source == .existing && workspace == .worktree && createdWorktree == nil {
            return "Create worktree & session"
        }
        return "Create session"
    }

    private var cloneDestinationHint: String {
        guard !trimmedParentDirectory.isEmpty else { return "" }
        let name = trimmedFolderName.isEmpty ? "repository" : trimmedFolderName
        return "Clones to \((trimmedParentDirectory as NSString).appendingPathComponent(name))"
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("New session")
                        .font(.system(size: 15, weight: .semibold))
                    Text(
                        createdSession == nil
                            ? (source == .clone
                                ? "Clone a repository, then start a session in it."
                                : "Pick a project and say what you need.")
                            : "Session created."
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
                Text("PROJECT")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                if createdSession == nil {
                    Picker("Project source", selection: $source) {
                        ForEach(Source.allCases) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(isWorking)
                }

                if source == .existing {
                    if !state.orderedProjects.isEmpty {
                        Button {
                            showingProjectPicker = true
                        } label: {
                            HStack(spacing: 8) {
                                ProjectIconView(
                                    image: selectedProject.flatMap { state.projectIcons[$0.id] },
                                    running: selectedRunningCount > 0,
                                    size: 26
                                )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(
                                        selectedProject?.displayName
                                            ?? (trimmedDirectory.isEmpty ? "Choose a project" : "Custom directory")
                                    )
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                    Text(shortDirectory)
                                        .font(.system(size: 8.5, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer(minLength: 6)

                                if selectedRunningCount > 0 {
                                    HStack(spacing: 3) {
                                        PulsingDot(size: 4)
                                        Text("\(selectedRunningCount)")
                                            .font(.system(size: 9, weight: .bold))
                                            .monospacedDigit()
                                    }
                                    .foregroundStyle(Theme.running)
                                }

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(createdSession != nil)
                        .help("Browse projects by name, path, running work, Git, and sandboxes")
                        .accessibilityLabel("Choose a project")
                        .accessibilityValue(selectedProject?.displayName ?? "Custom directory")
                    }

                    TextField("Project directory", text: $directory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .disabled(createdSession != nil)
                        .help("The folder OpenCode should work in")

                    if trimmedDirectory.isEmpty {
                        Text("Choose a project above, or type a custom folder path.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text("WORKSPACE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)

                        Picker("Workspace", selection: $workspace) {
                            ForEach(Workspace.allCases) { workspace in
                                Text(workspace.label).tag(workspace)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .disabled(isWorking || createdSession != nil || !canUseWorktree)

                        Text(workspaceHint)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 3)
                } else {
                    Text("REPOSITORY")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)

                    TextField("https://github.com/owner/repo or owner/repo", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .disabled(isWorking || createdSession != nil)
                        .help("Git URL, SSH remote, or GitHub owner/repo")

                    Button {
                        showingGitHubPicker = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Choose from GitHub")
                                .font(.system(size: 10, weight: .medium))
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking || createdSession != nil)
                    .help("Pick a repository from your GitHub account; already cloned repositories are disabled")

                    Text("CLONE INTO")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)

                    TextField("Parent folder on the Mac", text: $parentDirectory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .disabled(isWorking || createdSession != nil)
                        .help("The folder that receives the clone; ~ is supported")

                    Text("FOLDER NAME · OPTIONAL")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)

                    TextField("Use the repository name", text: $folderName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .disabled(isWorking || createdSession != nil)
                        .help("Leave blank to use the repository name")

                    if !cloneDestinationHint.isEmpty {
                        Text(cloneDestinationHint)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            modelAgentSection

            VStack(alignment: .leading, spacing: 5) {
                Text("TITLE · OPTIONAL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                TextField("Let OpenCode name it from the first message", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .disabled(createdSession != nil)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("FIRST MESSAGE · OPTIONAL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.system(size: 11))
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .padding(.trailing, 20)
                    .frame(height: 82)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        VoiceInputButton(dictation: dictation, text: $prompt, iconSize: 13)
                            .padding(3)
                            .disabled(isWorking)
                    }
                    .focused($promptFocused)
                    .disabled(isWorking)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("START")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)

                Picker("Start", selection: $startMode) {
                    ForEach(StartMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(isWorking)

                if startMode == .custom {
                    DatePicker(
                        "Start at",
                        selection: $customStart,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                }

                Text(startHint)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isCreatingWorktree {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Creating a Git worktree and running its setup…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .card(padding: 8)
                .accessibilityLabel("Creating a Git worktree")
            }

            if let createdSession {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                    Text("Session created. Fix the message and retry, or close this sheet to write it in the conversation.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(padding: 8)
                .accessibilityLabel("Session \(createdSession.displayTitle) created")
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn)
                    Text(errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card(padding: 8)
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isWorking)
                Button(actionTitle) {
                    Task { await submit() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!canSubmit)
            }
        }
        .padding(16)
        .frame(width: 420)
        .sheet(isPresented: $showingProjectPicker) {
            ProjectPickerSheet(
                projects: state.orderedProjects,
                icons: state.projectIcons,
                runningCounts: runningCounts,
                selection: trimmedDirectory
            ) { project in
                directory = project.canonical
            }
        }
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
        .sheet(isPresented: $showingGitHubPicker) {
            GitHubRepoPickerSheet { repository in
                repositoryURL = repository.cloneURL
                folderName = repository.name
            }
        }
        .task(id: catalogDirectory) {
            await loadCatalogs()
        }
        .onChange(of: modelChoice) { _, _ in
            guard let model = selectedModel else { return }
            let variants = model.variants ?? []
            if !variants.contains(where: { $0.id == selectedVariant }) {
                selectedVariant = nil
            }
        }
        .onAppear {
            if trimmedDirectory.isEmpty {
                directory = state.orderedProjects.first?.canonical ?? ""
            }
            if trimmedParentDirectory.isEmpty {
                parentDirectory = defaultParentDirectory
            }
            state.loadProjectIcons(for: state.orderedProjects)
            promptFocused = true
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
        .onExitCommand { dismiss() }
        .onDisappear { dictation.cancel() }
    }

    private var defaultParentDirectory: String {
        let seed = trimmedDirectory.isEmpty
            ? state.orderedProjects.first?.canonical ?? ""
            : trimmedDirectory
        guard !seed.isEmpty else { return "~/Developer" }
        let parent = (seed as NSString).deletingLastPathComponent
        return parent.isEmpty ? "~/Developer" : parent
    }

    private var modelAgentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if catalogsLoading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Loading OpenCode models and agents…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if catalogDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("MODEL AND AGENT · OPTIONAL")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text("Choose a project or folder to load available models and agents.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("MODEL · OPTIONAL")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if !models.isEmpty {
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
                            if selectedModel?.isFree == true {
                                Chip(text: "Free", tint: Theme.accent)
                            }
                            if modelChoice != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.accent)
                            }
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
                            ChoiceChip(title: "Default", isSelected: selectedVariant == nil) {
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
                        ChoiceChip(title: "Default", isSelected: selectedAgent == nil) {
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

                if let catalogError {
                    Text(catalogError)
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("OpenCodeBar never changes provider privacy settings or enables training on request data.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func resolveSessionDirectory() async throws -> String {
        guard createdSession == nil, source == .existing, workspace == .worktree else {
            return trimmedDirectory
        }
        guard let project = selectedProject, project.vcs == "git" else {
            throw NewSessionError.worktreeRequiresGitProject
        }
        if let createdWorktree {
            return createdWorktree.directory
        }

        isCreatingWorktree = true
        let worktree = try await state.createWorktree(projectID: project.id)
        createdWorktree = worktree
        isCreatingWorktree = false
        return worktree.directory
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
                    let cloned = try await state.cloneRepository(
                        url: trimmedRepositoryURL,
                        parent: trimmedParentDirectory,
                        name: trimmedFolderName
                    )
                    clonedRepository = cloned
                    directory = cloned.directory
                }
            }

            let sessionDirectory = try await resolveSessionDirectory()
            let session: Session
            if let createdSession {
                session = createdSession
            } else {
                session = try await state.createSession(
                    title: title,
                    directory: sessionDirectory
                )
                createdSession = session
            }

            if let model = selectedModelRef {
                try await state.switchModel(id: session.id, model: model)
            }
            if let agent = selectedAgent?.trimmingCharacters(in: .whitespacesAndNewlines),
               !agent.isEmpty {
                try await state.switchAgent(id: session.id, agent: agent)
            }

            let message = trimmedPrompt
            if !message.isEmpty {
                try await state.promptSession(
                    id: session.id,
                    text: message,
                    startAt: scheduledStart
                )
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }

    /// Starts from the model chosen most recently in any picker, as long as it
    /// is still offered for this directory.
    private func restoreLastModelSelection() {
        guard let last = ModelPreferences.lastSelection,
              let model = models.first(where: { $0.choice == last.choice })
        else { return }
        modelChoice = model.choice
        let variants = model.variants ?? []
        if let variant = last.variant, variants.contains(where: { $0.id == variant }) {
            selectedVariant = variant
        } else {
            selectedVariant = nil
        }
    }

    private func loadCatalogs() async {
        #if DEBUG
        if previewCatalogsProvided { return }
        #endif
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
        async let modelList = state.modelCatalog(directory: dir)
        async let agentList = state.agentCatalog(directory: dir)
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
            }
            if self.modelChoice == nil {
                restoreLastModelSelection()
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

private enum NewSessionError: LocalizedError {
    case worktreeRequiresGitProject

    var errorDescription: String? {
        switch self {
        case .worktreeRequiresGitProject:
            return "Select a known Git project to create a worktree."
        }
    }
}
