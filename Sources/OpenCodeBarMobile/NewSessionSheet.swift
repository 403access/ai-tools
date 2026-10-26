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

    @State private var directory: String
    @State private var title = ""
    @State private var prompt = ""
    @State private var source: Source = .existing
    @State private var repositoryURL = ""
    @State private var parentDirectory = ""
    @State private var folderName = ""
    @State private var clonedRepository: ClonedRepository?
    @State private var isCloning = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var createdSession: Session?
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

    private var canSubmit: Bool {
        guard !isWorking else { return false }
        switch source {
        case .existing:
            return !trimmedDirectory.isEmpty
        case .clone:
            return !trimmedRepositoryURL.isEmpty && !trimmedParentDirectory.isEmpty
        }
    }

    private var actionTitle: String {
        if createdSession != nil { return "Send" }
        if source == .clone && clonedRepository == nil { return "Clone & start" }
        return "Start"
    }

    private var progressLabel: String {
        if isCloning { return "Cloning repository…" }
        return createdSession == nil ? "Creating session…" : "Sending…"
    }

    private var cloneDestinationHint: String {
        guard !trimmedParentDirectory.isEmpty else { return "" }
        let name = trimmedFolderName.isEmpty ? "repository" : trimmedFolderName
        return (trimmedParentDirectory as NSString).appendingPathComponent(name)
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
                    titleSection
                    messageSection

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
            promptFocused = true
        }
        .onChange(of: source) { _, _ in clonedRepository = nil }
        .onChange(of: repositoryURL) { _, _ in clonedRepository = nil }
        .onChange(of: parentDirectory) { _, _ in clonedRepository = nil }
        .onChange(of: folderName) { _, _ in clonedRepository = nil }
        .onDisappear { dictation.cancel() }
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
                    Picker("Project", selection: $directory) {
                        ForEach(store.orderedProjects) { project in
                            Text(project.displayName).tag(project.canonical)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Theme.accent)
                    .disabled(createdSession != nil)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(MobileTheme.field)
                    )
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

            HStack(alignment: .bottom, spacing: 8) {
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

    private var shortPath: String {
        trimmedDirectory.isEmpty
            ? "Choose a folder on your Mac"
            : (trimmedDirectory as NSString).abbreviatingWithTildeInPath
    }

    private func submit() async {
        dictation.cancel()
        guard canSubmit else { return }

        isWorking = true
        errorMessage = nil
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

            let session: Session
            if let createdSession {
                session = createdSession
            } else {
                session = try await store.createSession(
                    title: title,
                    directory: trimmedDirectory
                )
                createdSession = session
            }

            let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                try await store.promptSession(id: session.id, text: message)
            }

            onCreated(session)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isCloning = false
        isWorking = false
    }
}
