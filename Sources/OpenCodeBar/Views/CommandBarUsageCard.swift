import SwiftUI

/// Usage specific to the persistent OpenCode conversation behind ⌘↵. The
/// session is still a normal OpenCode session; this card gives the feature a
/// labeled place in the Usage dashboard instead of folding it into project spend.
struct CommandBarUsageCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let usage = state.commandBarUsage {
                if usage.prompts > 0 {
                    metrics(usage)
                    if !usage.entries.isEmpty {
                        Divider().opacity(0.45)
                        VStack(spacing: 7) {
                            ForEach(usage.entries) { entry in
                                entryRow(entry)
                            }
                        }
                    }
                } else {
                    empty
                }
            } else if state.commandBarSessionID == nil {
                empty
            } else if let error = state.commandBarUsageError {
                errorState(error)
            } else {
                loading
            }
        }
        .card()
        .task { await state.refreshCommandBarUsage() }
        .onChange(of: state.connection) { _, _ in
            Task { await state.refreshCommandBarUsage(force: true) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.reasoning.opacity(0.14))
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.reasoning)
            }
            .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Command bar")
                    .font(.system(size: 12, weight: .semibold))
                Text(headerDetail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if state.commandBarUsageStale {
                Chip(text: "Cached", tint: Theme.warn)
            }

            if let usage = state.commandBarUsage, usage.prompts > 0 {
                Button {
                    open(usage.session)
                } label: {
                    HStack(spacing: 3) {
                        Text("Open session")
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .help("Open the command-bar conversation")
            }
        }
    }

    private var headerDetail: String {
        guard let usage = state.commandBarUsage else {
            return state.commandBarSessionID == nil
                ? "Prompts sent with ⌘↵"
                : "Loading usage…"
        }
        var parts: [String] = []
        if let model = usage.model { parts.append(model.label) }
        parts.append("updated \(Fmt.relative(from: usage.updated))")
        return parts.joined(separator: " · ")
    }

    private func metrics(_ usage: CommandBarUsage) -> some View {
        HStack(spacing: 10) {
            metric("Prompts", Fmt.grouped(usage.prompts), Theme.accent)
            metric("Cost", Fmt.usd(usage.cost), Theme.accent)
            metric("Tokens", Fmt.compact(usage.tokens.generated), Theme.reasoning)
        }
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func entryRow(_ entry: CommandBarUsageEntry) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.reasoning)
                .frame(width: 13, height: 14)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.prompt)
                    .font(.system(size: 10.5))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(Fmt.relative(from: entry.createdAt))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    if let model = entry.model {
                        Text(model.label)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if entry.cost > 0 {
                        Text(Fmt.usd(entry.cost))
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if entry.tokens.generated > 0 {
                        Text("\(Fmt.compact(entry.tokens.generated)) tok")
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if let duration = entry.durationMilliseconds {
                        Text(Fmt.duration(milliseconds: duration))
                            .font(.system(size: 9))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 2)

            if let outcome = entry.outcome, outcome != "completed" {
                Chip(
                    text: outcome.capitalized,
                    tint: outcome == "failed" ? Theme.danger : Theme.warn
                )
            }
        }
    }

    private var empty: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.reasoning)
            VStack(alignment: .leading, spacing: 2) {
                Text("No command-bar prompts yet")
                    .font(.system(size: 11, weight: .medium))
                Text("Press ⌘↵ in the command bar to ask the OpenCode agent.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var loading: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading command-bar usage…")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func errorState(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn’t load command-bar usage")
                    .font(.system(size: 11, weight: .medium))
                Text(message)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private func open(_ session: Session) {
        state.tab = .tasks
        state.open(session)
    }
}
