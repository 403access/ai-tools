import AppKit
import SwiftUI

/// Developer tools in Settings: an in-memory activity log for hub requests,
/// sync cycles, event-stream transitions, and app errors.
struct SettingsDeveloperSection: View {
    @ObservedObject private var log = DevLog.shared

    @State private var filter: DevLog.Filter = .all
    @State private var query = ""
    @State private var isPaused = false
    @State private var pausedEntries: [DevLog.Entry] = []
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Developer") {
                HStack(spacing: 6) {
                    if isPaused {
                        Chip(text: "Paused", systemImage: "pause.fill", tint: Theme.warn)
                    }
                    if log.issueCount > 0 {
                        Chip(
                            text: "\(log.issueCount) issue\(log.issueCount == 1 ? "" : "s")",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: Theme.danger
                        )
                    }
                    Text("\(log.entries.count) entries")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Picker("Filter", selection: $filter) {
                        ForEach(DevLog.Filter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 96)
                    .help("Filter by activity type")

                    TextField("Filter entries", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Clear the search filter")
                        .accessibilityLabel("Clear the search filter")
                    }
                }

                activityList

                HStack(spacing: 8) {
                    Text("In memory only. No tokens or request bodies.")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        togglePause()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    }
                    .help(isPaused ? "Resume live updates" : "Pause live updates")
                    .accessibilityLabel(isPaused ? "Resume live updates" : "Pause live updates")

                    Button {
                        copyLog()
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy the visible log")
                    .accessibilityLabel(copied ? "Copied" : "Copy the visible log")

                    Button {
                        clearLog()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear the log")
                    .accessibilityLabel("Clear the log")
                }
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.borderless)
            }
            .card()
        }
        .onDisappear {
            isPaused = false
            pausedEntries = []
        }
    }

    @ViewBuilder
    private var activityList: some View {
        let entries = visibleEntries

        if entries.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "ladybug")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text(emptyTitle)
                    .font(.system(size: 11, weight: .medium))
                Text("Hub requests, sync cycles, and event-stream changes appear here as they happen.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(listBackground)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        DeveloperLogRow(entry: entry)

                        if entry.id != entries.last?.id {
                            Divider().opacity(0.45)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(height: 230)
            .background(listBackground)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
        }
    }

    private var listBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.primary.opacity(0.035))
    }

    private var sourceEntries: [DevLog.Entry] {
        isPaused ? pausedEntries : log.entries
    }

    private var visibleEntries: [DevLog.Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sourceEntries.filter { entry in
            guard filter.matches(entry) else { return false }
            guard !needle.isEmpty else { return true }
            return entry.title.localizedCaseInsensitiveContains(needle)
                || (entry.detail?.localizedCaseInsensitiveContains(needle) ?? false)
                || entry.category.rawValue.localizedCaseInsensitiveContains(needle)
        }
    }

    private var emptyTitle: String {
        if log.entries.isEmpty && !isPaused { return "No activity yet" }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No matching entries"
        }
        if filter == .all { return "No activity yet" }
        return "No \(filter.rawValue.lowercased()) entries"
    }

    // MARK: - Actions

    private func togglePause() {
        if isPaused {
            isPaused = false
            pausedEntries = []
        } else {
            pausedEntries = log.entries
            isPaused = true
        }
    }

    private func copyLog() {
        let entries = visibleEntries
        guard !entries.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DevLog.text(for: entries), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copied = false
        }
    }

    private func clearLog() {
        log.clear()
        isPaused = false
        pausedEntries = []
    }
}

private struct DeveloperLogRow: View {
    let entry: DevLog.Entry

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 50, alignment: .leading)
                .padding(.top, 1)

            Text(entry.category.rawValue.uppercased())
                .font(.system(size: 8, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(tint)
                .frame(width: 36, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 10, weight: entry.level.isIssue ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(entry.level == .error ? Theme.danger : .primary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(entry.level == .error ? Theme.danger.opacity(0.9) : Color.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .textSelection(.enabled)

            Spacer(minLength: 2)

            if entry.level.isIssue {
                Image(systemName: entry.level == .error
                      ? "exclamationmark.triangle.fill"
                      : "exclamationmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(entry.level == .error ? Theme.danger : Theme.warn)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        if entry.level == .error { return Theme.danger }
        if entry.level == .warning { return Theme.warn }

        switch entry.category {
        case .api: return Theme.input
        case .sync: return Theme.accent
        case .events: return Theme.reasoning
        case .app: return Color.secondary
        }
    }
}
