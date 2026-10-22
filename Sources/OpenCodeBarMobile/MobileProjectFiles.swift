import SwiftUI

/// Browses every file in a project folder. Git working-tree changes are marked
/// inline, and the All / Changed switch narrows the list without a second
/// request.
struct MobileProjectFilesView: View {
    let files: ProjectFiles
    var onRefresh: (() -> Void)?

    @State private var filter: Filter = .all
    @State private var query = ""

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case changed = "Changed"

        var id: String { rawValue }
    }

    /// Computed once per body; the previous computed property was read three
    /// times on every keystroke.
    private func visibleFiles() -> [ProjectFile] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = files.files
        guard !needle.isEmpty else {
            guard filter == .changed else { return source }
            return source.filter(\.isChanged)
        }
        return source.filter { file in
            if filter == .changed && !file.isChanged { return false }
            return file.path.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        let visible = visibleFiles()
        return VStack(alignment: .leading, spacing: 9) {
            controls
            searchField

            if files.vcs == nil {
                Text("This folder is not a git work tree, so change status is unavailable.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if visible.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(emptyLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, file in
                        fileRow(file)
                        if index != visible.count - 1 {
                            Divider().opacity(0.25)
                        }
                    }
                }
            }

            if files.truncated {
                Text("Showing the first \(files.files.count) of \(files.total) files.")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
            }
        }
        .card(padding: 11)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Picker("Files", selection: $filter) {
                ForEach(Filter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)

            Text("\(files.total) files · \(files.changed) changed")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Reload files")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter files", text: $query)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private var emptyLabel: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No files match “\(query)”."
        }
        if filter == .changed {
            return files.vcs == nil ? "Change status needs a git repository." : "No changed files."
        }
        return "No files found."
    }

    private func fileRow(_ file: ProjectFile) -> some View {
        HStack(spacing: 7) {
            Image(systemName: file.statusIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint(for: file))
                .frame(width: 16)

            (Text(file.directory).foregroundColor(.secondary) + Text(file.name))
                .font(.system(size: 11.5, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 4)

            if file.isChanged {
                Text(file.statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint(for: file))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tint(for: file).opacity(0.12)))
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func tint(for file: ProjectFile) -> Color {
        switch file.status {
        case "added": return Theme.accent
        case "deleted": return Theme.danger
        case "renamed": return Theme.reasoning
        case "modified": return Theme.warn
        default: return .secondary
        }
    }
}
