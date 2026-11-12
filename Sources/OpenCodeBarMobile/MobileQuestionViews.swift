import SwiftUI

// The `question` tool is rendered as an inline card instead of a raw JSON
// block. Pending forms are answerable; completed calls stay as a compact Q&A
// summary in the conversation.

struct QuestionToolCard: View {
    let part: MessagePart
    let sessionID: String

    @EnvironmentObject private var store: MobileStore
    @State private var submittedAnswers: [[String]]?
    @State private var dismissed = false

    private var toolPartID: String? { part.id }

    private var form: FormInfo? {
        guard let toolPartID else { return nil }
        return store.pendingForm(sessionID: sessionID, toolPartID: toolPartID)
    }

    private var prompts: [QuestionPrompt] {
        let fromInput = part.questionPrompts
        if !fromInput.isEmpty { return fromInput }
        return (form?.fields ?? []).map { field in
            QuestionPrompt(
                header: field.displayTitle,
                question: field.displayQuestion,
                options: field.options ?? [],
                multiple: field.isMultiple,
                custom: field.allowsCustom
            )
        }
    }

    private var status: String { part.state?.status ?? "" }

    private var isFinished: Bool {
        status == "completed" || status == "error" || status == "failed"
    }

    private var errorText: String? {
        guard status == "error" || status == "failed",
              let error = part.state?.error
        else { return nil }
        let text = error.compactDescription
        return text.isEmpty ? nil : text
    }

    var body: some View {
        Group {
            if let errorText, prompts.isEmpty {
                QuestionNoticeCard(
                    icon: "exclamationmark.triangle.fill",
                    tint: Theme.danger,
                    title: "Question failed",
                    message: errorText
                )
            } else if status == "completed" {
                QuestionSummaryCard(
                    prompts: prompts,
                    answers: part.questionAnswers
                )
            } else if dismissed {
                QuestionSummaryCard(
                    prompts: prompts,
                    answers: [],
                    cancelled: "Dismissed"
                )
            } else if let submittedAnswers {
                QuestionSummaryCard(
                    prompts: prompts,
                    answers: submittedAnswers,
                    pending: true
                )
            } else if let errorText {
                QuestionSummaryCard(
                    prompts: prompts,
                    answers: [],
                    failed: errorText
                )
            } else if let form, !form.questions.isEmpty {
                QuestionFormView(
                    form: form,
                    submit: { answer in
                        try await store.replyForm(
                            sessionID,
                            formID: form.id,
                            answer: answer
                        )
                    },
                    onSubmitted: { answer in
                        submittedAnswers = answerArrays(answer, fields: form.fields)
                    },
                    cancel: { reason in
                        try await store.cancelForm(
                            sessionID,
                            formID: form.id,
                            message: reason
                        )
                    },
                    onCancelled: {
                        dismissed = true
                    }
                )
            } else {
                waitingCard
            }
        }
        .task(id: toolPartID) {
            guard !isFinished, form == nil else { return }
            await store.loadForms(sessionID)
        }
    }

    private var waitingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Question")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Preparing answer options…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView().controlSize(.small)
            }

            if let prompt = prompts.first {
                Text(prompt.header.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(Theme.accent)
                Text(prompt.question)
                    .font(.system(size: 15, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let error = store.sessionForms[sessionID]?.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Retry") {
                    Task { await store.loadForms(sessionID, force: true) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .questionCardChrome()
    }

    private func answerArrays(
        _ answer: [String: FormValue],
        fields: [FormField]
    ) -> [[String]] {
        fields.filter { !($0.hidden ?? false) }.map { field in
            switch answer[field.key] {
            case .string(let value)?:
                return value.isEmpty ? [] : [value]
            case .strings(let values)?:
                return values
            case .number(let value)?:
                return [value == value.rounded() ? String(Int(value)) : String(value)]
            case .bool(let value)?:
                return [value ? "Yes" : "No"]
            case nil:
                return []
            }
        }
    }
}

// MARK: - Answerable form

struct QuestionFormView: View {
    let form: FormInfo
    let submit: ([String: FormValue]) async throws -> Void
    let onSubmitted: ([String: FormValue]) -> Void
    let cancel: (String?) async throws -> Void
    let onCancelled: () -> Void

    @State private var currentIndex = 0
    @State private var selections: [String: Set<String>] = [:]
    @State private var customTexts: [String: String] = [:]
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showCancelConfirmation = false
    @FocusState private var focusedField: String?

    private var fields: [FormField] { form.questions }

    private var currentField: FormField? {
        guard fields.indices.contains(currentIndex) else { return fields.first }
        return fields[currentIndex]
    }

    private var isLast: Bool { currentIndex >= fields.count - 1 }

    init(
        form: FormInfo,
        submit: @escaping ([String: FormValue]) async throws -> Void,
        onSubmitted: @escaping ([String: FormValue]) -> Void,
        cancel: @escaping (String?) async throws -> Void,
        onCancelled: @escaping () -> Void
    ) {
        self.form = form
        self.submit = submit
        self.onSubmitted = onSubmitted
        self.cancel = cancel
        self.onCancelled = onCancelled

        var initialSelections: [String: Set<String>] = [:]
        var initialCustom: [String: String] = [:]
        for field in form.fields where !(field.hidden ?? false) {
            switch field.defaultValue {
            case .string(let value)?:
                if field.isChoice,
                   field.options?.contains(where: { $0.value == value }) == true {
                    initialSelections[field.key] = [value]
                } else if field.allowsCustom {
                    initialCustom[field.key] = value
                }
            case .array(let values)?:
                let strings = Set(values.compactMap(\.stringValue))
                if !strings.isEmpty { initialSelections[field.key] = strings }
            default:
                break
            }
        }
        _selections = State(initialValue: initialSelections)
        _customTexts = State(initialValue: initialCustom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            header
            progress

            if let field = currentField {
                question(field)
                    .id(field.key)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        )
                    )
            }

            if let errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(errorMessage)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.danger)
            }

            footer
        }
        .questionCardChrome()
        .confirmationDialog(
            "Dismiss this question?",
            isPresented: $showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button("Dismiss", role: .destructive) { dismiss() }
            Button("Keep answering", role: .cancel) {}
        } message: {
            Text("The agent will be told you dismissed the question.")
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 30, height: 30)
                Image(systemName: "questionmark.bubble.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(fields.count > 1 ? "Questions" : "Question")
                    .font(.system(size: 13, weight: .semibold))
                Text(fields.count > 1 ? "\(fields.count) questions for you" : "Waiting for your answer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Text("\(min(currentIndex + 1, fields.count)) of \(fields.count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                focusedField = nil
                showCancelConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting)
            .accessibilityLabel("Dismiss question")
        }
    }

    private var progress: some View {
        HStack(spacing: 4) {
            ForEach(fields.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= currentIndex ? Theme.accent : Color.primary.opacity(0.10))
                    .frame(height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: currentIndex)
    }

    @ViewBuilder
    private func question(_ field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(field.displayTitle.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(Theme.accent)

            Text(field.displayQuestion)
                .font(.system(size: 16, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if field.isChoice {
                VStack(spacing: 7) {
                    ForEach(field.options ?? []) { option in
                        optionRow(option, in: field)
                    }
                }
                .padding(.top, 1)
            }

            if field.allowsCustom {
                customAnswerField(field)
            }
        }
    }

    private func optionRow(_ option: FormOption, in field: FormField) -> some View {
        let selected = selections[field.key]?.contains(option.value) == true
        let multiple = field.isMultiple

        return Button {
            select(option, in: field)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected
                    ? (multiple ? "checkmark.square.fill" : "checkmark.circle.fill")
                    : (multiple ? "square" : "circle"))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.65))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        selected
                            ? Theme.accent.opacity(0.11)
                            : Color.primary.opacity(0.035)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        selected
                            ? Theme.accent.opacity(0.45)
                            : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func customAnswerField(_ field: FormField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10, weight: .semibold))
                Text(field.isChoice ? "Or type your own answer" : "Your answer")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.secondary)

            TextField(
                field.isMultiple ? "Add another answer…" : "Type your answer…",
                text: customBinding(for: field),
                axis: .vertical
            )
            .font(.system(size: 14))
            .lineLimit(1...4)
            .focused($focusedField, equals: field.key)
            .submitLabel(.done)
            .disabled(isSubmitting)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        focusedField == field.key
                            ? Theme.accent.opacity(0.45)
                            : Color.primary.opacity(0.08),
                        lineWidth: 1
                    )
            )
        }
        .onChange(of: customTexts[field.key] ?? "") { _, value in
            guard !field.isMultiple else { return }
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selections[field.key] = []
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if currentIndex > 0 {
                Button {
                    focusedField = nil
                    withAnimation(.snappy(duration: 0.24)) { currentIndex -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isSubmitting)
            }

            Spacer(minLength: 0)

            if isLast {
                Button(action: submitAnswer) {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(isSubmitting ? "Sending…" : "Submit")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isSubmitting || !canAdvance)
            } else {
                Button {
                    focusedField = nil
                    withAnimation(.snappy(duration: 0.24)) { currentIndex += 1 }
                } label: {
                    HStack(spacing: 5) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(isSubmitting || !canAdvance)
            }
        }
        .padding(.top, 1)
    }

    // MARK: Interaction

    private var canAdvance: Bool {
        guard let field = currentField else { return false }
        guard field.required == true || (field.minItems ?? 0) > 0 else { return true }
        let minimum = max(field.minItems ?? 0, field.required == true ? 1 : 0)
        return answerCount(for: field) >= minimum
    }

    private func answerCount(for field: FormField) -> Int {
        var count = selections[field.key]?.count ?? 0
        let custom = (customTexts[field.key] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { count += 1 }
        return count
    }

    private func select(_ option: FormOption, in field: FormField) {
        var selected = selections[field.key] ?? []
        if field.isMultiple {
            if selected.contains(option.value) {
                selected.remove(option.value)
            } else {
                selected.insert(option.value)
            }
        } else {
            selected = selected.contains(option.value) ? [] : [option.value]
            customTexts[field.key] = ""
        }
        selections[field.key] = selected
        errorMessage = nil
    }

    private func customBinding(for field: FormField) -> Binding<String> {
        Binding(
            get: { customTexts[field.key] ?? "" },
            set: { value in
                customTexts[field.key] = value
                errorMessage = nil
            }
        )
    }

    private func answerValue(for field: FormField) -> FormValue? {
        let custom = (customTexts[field.key] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if field.isMultiple {
            var values = (field.options ?? [])
                .filter { selections[field.key]?.contains($0.value) == true }
                .map(\.value)
            if !custom.isEmpty { values.append(custom) }
            return values.isEmpty ? nil : .strings(values)
        }

        if !custom.isEmpty { return .string(custom) }
        if let value = selections[field.key]?.first { return .string(value) }
        return nil
    }

    private var answer: [String: FormValue] {
        var result: [String: FormValue] = [:]
        for field in form.fields where !(field.hidden ?? false) {
            if let value = answerValue(for: field) {
                result[field.key] = value
            }
        }
        return result
    }

    private func submitAnswer() {
        guard !isSubmitting else { return }
        focusedField = nil
        isSubmitting = true
        errorMessage = nil
        let payload = answer

        Task { @MainActor in
            do {
                try await submit(payload)
                onSubmitted(payload)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func dismiss() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await cancel(nil)
                onCancelled()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }
}

// MARK: - Completed summary

struct QuestionSummaryCard: View {
    let prompts: [QuestionPrompt]
    let answers: [[String]]
    var cancelled: String?
    var pending = false
    var failed: String?

    private var tint: Color {
        if failed != nil { return Theme.danger }
        if cancelled != nil { return .secondary }
        return Theme.accent
    }

    private var icon: String {
        if failed != nil { return "exclamationmark.triangle.fill" }
        if cancelled != nil { return "xmark.circle.fill" }
        if pending { return "paperplane.fill" }
        return "checkmark.circle.fill"
    }

    private var title: String {
        if failed != nil { return "Question failed" }
        if cancelled != nil { return "Question dismissed" }
        if pending { return "Sending answer…" }
        return prompts.count > 1 ? "Questions answered" : "Question answered"
    }

    private var subtitle: String {
        if let failed, !failed.isEmpty { return failed }
        if let cancelled, !cancelled.isEmpty { return cancelled }
        if pending { return "Waiting for the agent to continue" }
        return "The agent has your answer"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if pending {
                    ProgressView().controlSize(.small)
                }
            }

            if prompts.isEmpty {
                Text(cancelled == nil
                    ? "The agent did not record the question text."
                    : "No answer was sent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 11) {
                    ForEach(Array(prompts.enumerated()), id: \.offset) { index, prompt in
                        summaryRow(prompt, answers: answerValues(at: index))
                    }
                }
            }
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(cancelled == nil && failed == nil ? 0.055 : 0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    tint.opacity(cancelled == nil && failed == nil ? 0.22 : 0.12),
                    lineWidth: 1
                )
        )
    }

    private func answerValues(at index: Int) -> [String] {
        guard answers.indices.contains(index) else { return [] }
        return answers[index].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func summaryRow(_ prompt: QuestionPrompt, answers: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(prompt.header.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(tint.opacity(cancelled == nil ? 1 : 0.8))

            Text(prompt.question)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            if answers.isEmpty {
                Text(cancelled != nil ? "Dismissed" : "No answer")
                    .font(.system(size: 12))
                    .italic()
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: cancelled == nil ? "checkmark" : "minus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(tint)
                                .padding(.top, 2)
                            Text(answer)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
    }
}

struct QuestionNoticeCard: View {
    let icon: String
    let tint: Color
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

// MARK: - Shared chrome

private extension View {
    func questionCardChrome() -> some View {
        padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(0.075),
                                Color.primary.opacity(0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
            )
    }
}
