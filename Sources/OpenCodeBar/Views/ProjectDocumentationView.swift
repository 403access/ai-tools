import SwiftUI

// MARK: - Project documentation

/// The Docs tab on a project detail page. The brief is editable; the product
/// and technical feature lists are derived automatically from prompts, with
/// every entry keeping a link back to the task and session that produced it.
struct ProjectDocumentationView: View {
    let documentation: ProjectDocumentation
    var isRefreshing = false
    let onRefresh: () -> Void
    var onEdit: (() -> Void)?
    var onOpenSession: ((String) -> Void)?

    var body: some View {
        SectionHeader("Project brief") {
            HStack(spacing: 6) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.65)
                }

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh project documentation")

                if let onEdit {
                    Button(action: onEdit) {
                        HStack(spacing: 3) {
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                            Text("Edit")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .help("Edit the description, mission, and vision")
                }
            }
        }

        brief

        SectionHeader("Product features") {
            count(documentation.productFeatures.count)
        }
        featureSection(
            documentation.productFeatures,
            emptyTitle: "No product documentation yet",
            emptySubtitle: "Prompts about user-facing features, fixes, and experience changes appear here."
        )

        SectionHeader("Technical features") {
            count(documentation.technicalFeatures.count)
        }
        featureSection(
            documentation.technicalFeatures,
            emptyTitle: "No technical documentation yet",
            emptySubtitle: "Prompts about APIs, architecture, tooling, and infrastructure appear here."
        )
    }

    private var brief: some View {
        VStack(alignment: .leading, spacing: 9) {
            briefField(
                "Description",
                icon: "text.alignleft",
                text: documentation.description,
                placeholder: "Describe what this project is and who it is for."
            )
            Divider().opacity(0.35)
            briefField(
                "Mission",
                icon: "scope",
                text: documentation.mission,
                placeholder: "Add the mission this project is working toward."
            )
            Divider().opacity(0.35)
            briefField(
                "Vision",
                icon: "sparkles",
                text: documentation.vision,
                placeholder: "Add the long-term outcome this project should reach."
            )

            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 8, weight: .bold))
                Text("Updated \(Fmt.relative(from: documentation.updatedDate))")
                    .font(.system(size: 9))
                Spacer(minLength: 0)
                Text("\(documentation.featureCount) documented changes")
                    .font(.system(size: 9))
            }
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private func briefField(
        _ title: String,
        icon: String,
        text: String,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
            }
            .foregroundStyle(.secondary)

            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty {
                Text(placeholder)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .italic()
            } else {
                Text(value)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func count(_ value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 10, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func featureSection(
        _ entries: [ProjectFeatureDoc],
        emptyTitle: String,
        emptySubtitle: String
    ) -> some View {
        if entries.isEmpty {
            EmptyState(icon: "book.closed", title: emptyTitle, subtitle: emptySubtitle)
        } else {
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    ProjectFeatureDocRow(
                        entry: entry,
                        onOpenSession: onOpenSession.map { open in
                            { open(entry.sessionID) }
                        }
                    )

                    if entry.id != entries.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
            .card(padding: 10)
        }
    }
}

/// One prompt-derived documentation entry. The action chip says whether the
/// prompt added, updated, or removed something; the footer names the task and
/// session that produced the entry.
struct ProjectFeatureDocRow: View {
    let entry: ProjectFeatureDoc
    var onOpenSession: (() -> Void)? = nil

    private var actionTint: Color {
        switch entry.action {
        case .new: return Theme.accent
        case .update: return Theme.input
        case .remove: return Theme.danger
        }
    }

    private var categoryTint: Color {
        switch entry.category {
        case "feature": return Theme.accent
        case "bug", "security": return Theme.danger
        case "performance": return Theme.warn
        case "refactor": return Theme.reasoning
        case "tests", "docs": return Theme.input
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: entry.action.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(actionTint)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.system(size: 11, weight: .medium))
                        .strikethrough(entry.action == .remove, color: .secondary)
                        .foregroundStyle(entry.action == .remove ? .secondary : .primary)
                        .lineLimit(2)

                    HStack(spacing: 4) {
                        Chip(text: entry.categoryTitle, tint: categoryTint)
                        Chip(text: entry.action.title, tint: actionTint)
                        ForEach(entry.labels.filter { $0.id != entry.category }) { label in
                            Chip(text: label.title, tint: labelTint(label.kind))
                        }
                        Spacer(minLength: 0)
                        Text(Fmt.relative(from: entry.createdDate))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if !entry.detail.isEmpty {
                Text(entry.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 17)
            }

            if let onOpenSession {
                Button(action: onOpenSession) {
                    taskReference
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .padding(.leading, 17)
                .help("Open the session that produced this entry")
            } else {
                taskReference
                    .foregroundStyle(.secondary)
                    .padding(.leading, 17)
            }
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var taskReference: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 8, weight: .bold))
            Text("Task")
                .font(.system(size: 9, weight: .bold))
            Text(entry.taskTitle.isEmpty ? entry.title : entry.taskTitle)
                .font(.system(size: 9))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("·")
                .font(.system(size: 9))
            Text(entry.sessionID)
                .font(.system(size: 9, design: .monospaced))
                .lineLimit(1)
        }
    }

    private func labelTint(_ kind: String) -> Color {
        switch kind {
        case "risk": return Theme.danger
        case "scope": return Theme.reasoning
        default: return .secondary
        }
    }
}

/// Placeholder while the project's documentation loads for the first time.
struct ProjectDocumentationSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SkeletonBlock(width: 130, height: 12)
            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 90, height: 8)
                SkeletonBlock(height: 10)
                SkeletonBlock(height: 10)
                SkeletonBlock(width: 210, height: 10)
                SkeletonBlock(width: 70, height: 8)
                SkeletonBlock(height: 10)
                SkeletonBlock(width: 180, height: 10)
            }
            .card(padding: 10)

            SkeletonBlock(width: 150, height: 12)
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 6) {
                    SkeletonBlock(width: 200, height: 10)
                    SkeletonBlock(height: 9)
                    SkeletonBlock(width: 130, height: 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 10)
            }
        }
    }
}

// MARK: - Editor

/// Sheet for the editable half of the Docs tab. Feature documentation is not
/// editable because it is a record of prompts that were actually sent.
struct ProjectDocumentationEditor: View {
    @Environment(\.dismiss) private var dismiss

    let projectName: String
    let documentation: ProjectDocumentation
    let onSave: (String, String, String) async throws -> Void

    @State private var description: String
    @State private var mission: String
    @State private var vision: String
    @State private var isSaving = false
    @State private var error: String?

    init(
        projectName: String,
        documentation: ProjectDocumentation,
        onSave: @escaping (String, String, String) async throws -> Void
    ) {
        self.projectName = projectName
        self.documentation = documentation
        self.onSave = onSave
        _description = State(initialValue: documentation.description)
        _mission = State(initialValue: documentation.mission)
        _vision = State(initialValue: documentation.vision)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit project documentation")
                        .font(.system(size: 14, weight: .semibold))
                    Text(projectName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    editorField(
                        "Description",
                        hint: "What the project is and who it serves.",
                        text: $description
                    )
                    editorField(
                        "Mission",
                        hint: "What the project is here to accomplish now.",
                        text: $mission
                    )
                    editorField(
                        "Vision",
                        hint: "The long-term outcome the project should reach.",
                        text: $vision
                    )
                }
                .padding(.bottom, 4)
            }

            if let error {
                NoticeRow(
                    icon: "exclamationmark.triangle.fill",
                    message: error,
                    tint: Theme.warn
                )
            }

            HStack {
                Text("Feature documentation is generated from prompts and is read-only.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(action: save) {
                    Text(isSaving ? "Saving…" : "Save")
                        .font(.system(size: 11, weight: .semibold))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
            }
        }
        .padding(16)
        .frame(width: 540, height: 520)
    }

    private func editorField(
        _ title: String,
        hint: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(hint)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            TextEditor(text: text)
                .font(.system(size: 11))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 105)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
                )
                .disabled(isSaving)
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        error = nil
        Task { @MainActor in
            do {
                try await onSave(description, mission, vision)
                dismiss()
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isSaving = false
        }
    }
}
