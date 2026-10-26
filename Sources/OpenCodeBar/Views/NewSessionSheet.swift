import SwiftUI

/// Starts a new OpenCode session in a project directory, optionally with a
/// first prompt. Opened from the Live tab or a project's detail page.
struct NewSessionSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    private enum Source: String, CaseIterable, Identifiable {
        case existing
        case clone

        var id: String { rawValue }
        var label: String { self == .existing ? "Existing folder" : "Clone repository" }
    }

    @State private var directory: String
    @State private var title = ""
    @State private var prompt = ""
    @State private var source: Source = .existing
    @State private var repositoryURL = ""
    @State private var parentDirectory = ""
    @State private var folderName = ""
    @State private var clonedRepository: ClonedRepository?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var createdSession: Session?
    @StateObject private var dictation = SpeechDictation()
    @FocusState private var promptFocused: Bool

    init(directory: String? = nil) {
        _directory = State(initialValue: directory ?? "")
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

    private var projectLabel: String {
        state.orderedProjects.first(where: { $0.canonical == trimmedDirectory })?.displayName
            ?? "Custom directory"
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
        if createdSession != nil { return "Send message" }
        if source == .clone && clonedRepository == nil { return "Clone & create" }
        return "Create session"
    }

    private var cloneDestinationHint: String {
        guard !trimmedParentDirectory.isEmpty else { return "" }
        let name = trimmedFolderName.isEmpty ? "repository" : trimmedFolderName
        return "Clones to \((trimmedParentDirectory as NSString).appendingPathComponent(name))"
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
                        Picker("Project", selection: $directory) {
                            ForEach(state.orderedProjects) { project in
                                Text(project.displayName).tag(project.canonical)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .disabled(createdSession != nil)
                    }

                    TextField("Project directory", text: $directory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .disabled(createdSession != nil)
                        .help("The folder OpenCode should work in")

                    if !trimmedDirectory.isEmpty {
                        Text(projectLabel == "Custom directory" ? trimmedDirectory : projectLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    TextField("https://github.com/owner/repo or owner/repo", text: $repositoryURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                        .disabled(isWorking || createdSession != nil)
                        .help("Git URL, SSH remote, or GitHub owner/repo")

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
        .frame(width: 370)
        .onAppear {
            if trimmedDirectory.isEmpty {
                directory = state.orderedProjects.first?.canonical ?? ""
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
                    let cloned = try await state.cloneRepository(
                        url: trimmedRepositoryURL,
                        parent: trimmedParentDirectory,
                        name: trimmedFolderName
                    )
                    clonedRepository = cloned
                    directory = cloned.directory
                }
            }

            let session: Session
            if let createdSession {
                session = createdSession
            } else {
                session = try await state.createSession(
                    title: title,
                    directory: trimmedDirectory
                )
                createdSession = session
            }

            let message = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !message.isEmpty {
                try await state.promptSession(id: session.id, text: message)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isWorking = false
    }
}
