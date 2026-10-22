import SwiftUI

/// Browses every file in a project folder. Git working-tree changes are marked
/// inline, and the All / Changed switch narrows the list without a second
/// request.
struct ProjectFilesView: View {
    let files: ProjectFiles
    var onRefresh: (() -> Void)?

    @State private var filter: Filter = .all
    @State private var query = ""

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case changed = "Changed"

        var id: String { rawValue }
    }

    /// Computed once per body below; the previous computed property was read
    /// three times (empty check, count and the list), so a 20k-file project paid
    /// the full scan three times on every keystroke.
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
        return VStack(alignment: .leading, spacing: 7) {
            controls
            searchField

            if files.vcs == nil {
                Text("This folder is not a git work tree, so change status is unavailable.")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if visible.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text(emptyLabel)
                        .font(.system(size: 10))
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
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warn)
            }
        }
        .card(padding: 9)
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Picker("Files", selection: $filter) {
                ForEach(Filter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 128)

            Text("\(files.total) files · \(files.changed) changed")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Reload files")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter files", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
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
        HStack(spacing: 6) {
            Image(systemName: file.statusIcon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint(for: file))
                .frame(width: 12)

            (Text(file.directory).foregroundColor(.secondary) + Text(file.name))
                .font(.system(size: 9.5, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)

            Spacer(minLength: 4)

            if file.isChanged {
                Text(file.statusLabel)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint(for: file))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(tint(for: file).opacity(0.12)))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(file.path)
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
