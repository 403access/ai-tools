import SwiftUI

/// Mobile counterpart of the Mac New Session sheet. Creates a session in a
/// project directory and can send the first prompt in the same flow.
struct MobileNewSessionSheet: View {
    @EnvironmentObject private var store: MobileStore
    @Environment(\.dismiss) private var dismiss

    let onCreated: (Session) -> Void

    @State private var directory: String
    @State private var title = ""
    @State private var prompt = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var createdSession: Session?
    @FocusState private var promptFocused: Bool

    init(directory: String? = nil, onCreated: @escaping (Session) -> Void = { _ in }) {
        _directory = State(initialValue: directory ?? "")
        self.onCreated = onCreated
    }

    private var trimmedDirectory: String {
        directory.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedProject: Project? {
        store.orderedProjects.first { $0.canonical == trimmedDirectory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(
                        createdSession == nil
                            ? "Pick a project and say what you need. OpenCode starts in that folder."
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
                    Button(createdSession == nil ? "Start" : "Send") {
                        Task { await submit() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isWorking || trimmedDirectory.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isWorking {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(createdSession == nil ? "Creating session…" : "Sending…")
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
            promptFocused = true
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionHeader("Project") {
                if let selectedProject {
                    Chip(text: selectedProject.vcs ?? "folder", tint: Theme.accent)
                }
            }

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
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MobileTheme.field)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(MobileTheme.border, lineWidth: 1)
                )

            Text(shortPath)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
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

            TextField("What should OpenCode do?", text: $prompt, axis: .vertical)
                .font(.subheadline)
                .lineLimit(4...8)
                .focused($promptFocused)
                .submitLabel(.return)
                .disabled(isWorking)
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
        guard !isWorking, !trimmedDirectory.isEmpty else { return }

        isWorking = true
        errorMessage = nil
        do {
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
        isWorking = false
    }
}
