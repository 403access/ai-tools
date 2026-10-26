import SwiftUI
import UIKit

/// Full-screen developer activity log, opened from iPhone/iPad Settings.
struct DeveloperView: View {
    @ObservedObject private var log = DevLog.shared

    @State private var filter: DevLog.Filter = .all
    @State private var query = ""
    @State private var isPaused = false
    @State private var pausedEntries: [DevLog.Entry] = []
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summarySection
                controlsSection
                entriesSection
                sectionNote(
                    "The log lives in memory on this device, is cleared when the app quits, "
                        + "and never includes the hub token or request bodies."
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .mobileScreenBackground()
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            isPaused = false
            pausedEntries = []
        }
    }

    // MARK: - Summary

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Activity") {
                if isPaused {
                    Chip(text: "Paused", systemImage: "pause.fill", tint: Theme.warn)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(log.entries.count) entries")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()

                    Spacer(minLength: 4)

                    if log.issueCount > 0 {
                        Chip(
                            text: "\(log.issueCount) issue\(log.issueCount == 1 ? "" : "s")",
                            systemImage: "exclamationmark.triangle.fill",
                            tint: Theme.danger
                        )
                    }
                }

                Text("Hub requests, sync cycles, event-stream changes, and errors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 12)
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DevLog.Filter.allCases) { option in
                        filterChip(option)
                    }
                }
            }

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Filter entries", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear the search filter")
                }
            }
            .mobileField()

            HStack(spacing: 8) {
                Button {
                    togglePause()
                } label: {
                    Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    copyLog()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(visibleEntries.isEmpty)

                Button {
                    clearLog()
                } label: {
                    Label("Clear", systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.danger)
                .disabled(log.entries.isEmpty)
            }
        }
        .card(padding: 12)
    }

    private func filterChip(_ option: DevLog.Filter) -> some View {
        let selected = filter == option
        return Button {
            filter = option
        } label: {
            Text(option.rawValue)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
                .background(
                    Capsule().fill(selected ? Theme.accent.opacity(0.18) : MobileTheme.field)
                )
                .overlay(
                    Capsule().strokeBorder(selected ? Theme.accent.opacity(0.45) : MobileTheme.border)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Entries

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Log")

            let entries = visibleEntries

            if entries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "ladybug")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                    Text(emptyTitle)
                        .font(.subheadline.weight(.medium))
                    Text("Activity appears here as the app talks to the hub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .card(padding: 12)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        DeveloperLogRow(entry: entry)

                        if entry.id != entries.last?.id {
                            Divider().opacity(0.45)
                        }
                    }
                }
                .card(padding: 12)
            }
        }
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

        UIPasteboard.general.string = DevLog.text(for: entries)
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

    private func sectionNote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
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
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 54, alignment: .leading)
                .padding(.top, 1)

            Text(entry.category.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(tint)
                .frame(width: 40, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 11, weight: entry.level.isIssue ? .semibold : .medium, design: .monospaced))
                    .foregroundStyle(entry.level == .error ? Theme.danger : .primary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if let detail = entry.detail {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
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
                    .font(.system(size: 10))
                    .foregroundStyle(entry.level == .error ? Theme.danger : Theme.warn)
                    .padding(.top, 1)
            }
        }
        .padding(.vertical, 5)
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
