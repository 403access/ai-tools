import AppKit
import SwiftUI

// MARK: - Messages

struct MessageCard: View, Equatable {
    let message: SessionMessage

    var body: some View {
        if message.isUserLike {
            userCard
        } else {
            assistantCard
        }
    }

    private var userCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: message.isSynthetic ? "wand.and.stars" : "person.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(message.roleLabel)
                    .font(.system(size: 9, weight: .bold))
                Spacer()
                Text(Fmt.relative(from: message.time.createdDate))
                    .font(.system(size: 9))
            }
            .foregroundStyle(message.isSynthetic ? Theme.warn : Theme.accent)

            if let text = message.promptText {
                Text(text)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.accent.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.16), lineWidth: 1)
        )
    }

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.running)
                Text("Assistant")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.running)
                Spacer()
                Text(Fmt.relative(from: message.time.createdDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            let parts = message.content ?? []
            if parts.isEmpty {
                Text("Working…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    PartView(part: part)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }
}

private struct PartView: View {
    let part: MessagePart

    var body: some View {
        switch part.type {
        case "text":
            if let text = part.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case "reasoning":
            if let text = part.text, !text.isEmpty {
                ReasoningPartView(text: text)
            }
        case "tool":
            ToolPartView(part: part)
        default:
            if let text = part.text, !text.isEmpty {
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ReasoningPartView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.system(size: 8, weight: .bold))
                    Text("Reasoning")
                        .font(.system(size: 9, weight: .semibold))
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(Theme.reasoning)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineSpacing(1)
                .lineLimit(expanded ? nil : 2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.reasoning.opacity(0.08))
        )
    }
}

private struct ToolPartView: View {
    let part: MessagePart

    @State private var expanded = false

    private var status: String { part.state?.status ?? "unknown" }

    private var statusColor: Color {
        switch status {
        case "running": return Theme.running
        case "completed": return Theme.accent
        case "error", "failed": return Theme.danger
        default: return .secondary
        }
    }

    private var statusIcon: String {
        switch status {
        case "running": return "ellipsis"
        case "completed": return "checkmark"
        case "error", "failed": return "xmark"
        default: return "minus"
        }
    }

    private var fileChanges: [FileChange] { part.fileChanges }

    private var hasDetails: Bool {
        part.state?.input != nil || part.state?.outputText != nil || !fileChanges.isEmpty
    }

    private var outputText: String? {
        guard expanded, let output = part.state?.outputText else { return nil }
        if output.count > 4_000 {
            return String(output.prefix(4_000)) + "\n… truncated"
        }
        return output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                guard hasDetails else { return }
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(statusColor)
                    Text(part.name ?? "tool")
                        .font(.system(size: 9, weight: .semibold))
                    if let summary = part.state?.inputSummary {
                        Text(summary)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                    if status == "running" {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                    if hasDetails {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if !fileChanges.isEmpty {
                    ForEach(fileChanges) { change in
                        FileChangeCard(change: change)
                    }
                } else if let input = part.state?.input {
                    Text(input.prettyString())
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                }

                if let outputText {
                    Text(outputText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                }
            }
        }
        .padding(7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }
}

struct PromptRow: View, Equatable {
    let index: Int
    let message: SessionMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("#\(index)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
                if message.isSynthetic {
                    Chip(text: "system", tint: Theme.warn)
                }
                Spacer()
                Text(Fmt.relative(from: message.time.createdDate))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)

                Button {
                    copyToPasteboard(message.promptText ?? "")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy prompt")
            }

            if let text = message.promptText {
                Text(text)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
