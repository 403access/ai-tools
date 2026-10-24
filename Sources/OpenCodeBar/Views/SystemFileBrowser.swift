import AppKit
import SwiftUI

/// Read-only browser for the machine running the hub. It opens over the panel
/// (like a detail page) from the System tab, so Back returns to the tab.
struct SystemFileBrowser: View {
    @EnvironmentObject private var state: AppState

    @State private var path: String
    @State private var pathDraft: String
    @State private var listing: HostDirectory?
    @State private var isLoading = false
    @State private var error: String?
    @State private var query = ""
    @State private var showHidden = false
    @State private var previewPath: String?

    init(initialPath: String) {
        _path = State(initialValue: initialPath)
        _pathDraft = State(initialValue: initialPath)
    }

    var body: some View {
        Group {
            if let previewPath {
                HostFilePreview(path: previewPath) {
                    self.previewPath = nil
                }
            } else {
                browser
            }
        }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    pathFields
                    quickRoots
                    searchField

                    if let error {
                        NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                    }

                    if isLoading && listing == nil {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text("Reading folder…")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    } else if let listing {
                        entriesCard(listing)
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: .infinity)
        }
        .task(id: path) { await load(path) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                state.closeFileBrowser()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back to System")
            .accessibilityLabel("Back to System")

            VStack(alignment: .leading, spacing: 1) {
                Text("Files")
                    .font(.system(size: 13, weight: .semibold))
                Text(listing?.name ?? (path as NSString).lastPathComponent)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }

            Button {
                showHidden.toggle()
            } label: {
                Image(systemName: showHidden ? "eye" : "eye.slash")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showHidden ? Theme.accent : .secondary)
            .help(showHidden ? "Hide hidden files" : "Show hidden files")

            Button {
                Task { await load(path) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reload folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Path

    private var pathFields: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                TextField("Absolute path", text: $pathDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .onSubmit { navigate(to: pathDraft) }
                if pathDraft != path {
                    Button("Go") { navigate(to: pathDraft) }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(breadcrumbs, id: \.path) { crumb in
                        Button {
                            navigate(to: crumb.path)
                        } label: {
                            HStack(spacing: 3) {
                                if crumb.isRoot {
                                    Image(systemName: "internaldrive")
                                        .font(.system(size: 7, weight: .semibold))
                                }
                                Text(crumb.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(crumb.path == path ? Theme.accent : .secondary)
                        }
                        .buttonStyle(.plain)

                        if crumb.path != breadcrumbs.last?.path {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    private var quickRoots: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(quickRootsList) { root in
                    Button {
                        navigate(to: root.path)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: root.icon)
                                .font(.system(size: 8, weight: .semibold))
                            Text(root.name)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(root.path == path ? Theme.accent : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                root.path == path
                                    ? Theme.accent.opacity(0.14)
                                    : Color.primary.opacity(0.05)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(root.path)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter this folder", text: $query)
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
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    // MARK: - Entries

    private func entriesCard(_ listing: HostDirectory) -> some View {
        let entries = visibleEntries(listing)
        return VStack(alignment: .leading, spacing: 0) {
            if let parent = listing.parent {
                Button {
                    navigate(to: parent)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text("Parent folder")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(parent)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }

            if entries.isEmpty {
                Text(emptyLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        entryRow(entry)
                        if index != entries.count - 1 {
                            Divider().opacity(0.22)
                        }
                    }
                }
            }

            if listing.truncated {
                Divider().opacity(0.3)
                Text("Showing the first \(listing.entries.count) of \(Fmt.grouped(listing.total)) entries.")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.warn)
                    .padding(.top, 7)
            }
        }
        .card(padding: 9)
    }

    private func entryRow(_ entry: HostFileEntry) -> some View {
        Button {
            if entry.isDirectory {
                navigate(to: entry.path)
            } else {
                previewPath = entry.path
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: entry.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(entry.isDirectory ? Theme.accent : entry.kind == "symlink" ? Theme.reasoning : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(entry.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(entry.hidden ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if entry.kind == "symlink" {
                            Image(systemName: "link")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(Theme.reasoning)
                        }
                    }
                    if let target = entry.linkTarget {
                        Text(target)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    if let size = entry.size, !entry.isDirectory {
                        Text(Fmt.bytes(size))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let date = entry.modifiedDate {
                        Text(Fmt.relative(from: date))
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                }

                Image(systemName: entry.isDirectory ? "chevron.right" : "doc.text.magnifyingglass")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .help(entry.error ?? entry.path)
    }

    // MARK: - Data

    private func visibleEntries(_ listing: HostDirectory) -> [HostFileEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return listing.entries.filter { entry in
            if !showHidden && entry.hidden { return false }
            guard !needle.isEmpty else { return true }
            return entry.name.localizedCaseInsensitiveContains(needle)
                || entry.path.localizedCaseInsensitiveContains(needle)
        }
    }

    private var emptyLabel: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No entries match “\(query)”."
        }
        if !showHidden && (listing?.entries.contains(where: \.hidden) ?? false) {
            return "This folder only contains hidden files."
        }
        return "This folder is empty."
    }

    private func navigate(to target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        query = ""
        pathDraft = trimmed
        if trimmed == path {
            Task { await load(trimmed) }
        } else {
            path = trimmed
        }
    }

    private func load(_ target: String) async {
        if state.api == nil { await state.bootstrap() }
        guard let api = state.api else {
            error = "The hub is not connected."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.hostFiles(path: target)
            listing = result
            pathDraft = result.path
            if result.path != path {
                path = result.path
            }
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Breadcrumbs and roots

    private struct Crumb {
        let name: String
        let path: String
        let isRoot: Bool
    }

    private var breadcrumbs: [Crumb] {
        if path.contains("\\") {
            let parts = path.split(separator: "\\", omittingEmptySubsequences: true)
            var result: [Crumb] = []
            var current = ""
            for (index, part) in parts.enumerated() {
                current = index == 0 ? "\(part)\\" : "\(current)\(part)\\"
                result.append(Crumb(name: String(part), path: current, isRoot: index == 0))
            }
            return result
        }

        var result = [Crumb(name: "/", path: "/", isRoot: true)]
        var current = ""
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            current += "/\(part)"
            result.append(Crumb(name: String(part), path: current, isRoot: false))
        }
        return result
    }

    private var quickRootsList: [HostFileRoot] {
        var values = listing?.roots ?? []
        for project in state.orderedProjects.prefix(10) {
            values.append(HostFileRoot(name: project.displayName, path: project.canonical, kind: "project"))
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.path).inserted }
    }
}

// MARK: - File preview

private struct HostFilePreview: View {
    @EnvironmentObject private var state: AppState

    let path: String
    let onBack: () -> Void

    @State private var content: HostFileContent?
    @State private var image: NSImage?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)

            if isLoading && content == nil {
                VStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Reading file…")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 8) {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                }
                .padding(12)
            } else if let content {
                ScrollView([.horizontal, .vertical]) {
                    Group {
                        if content.isImage, let image {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .padding(12)
                        } else if content.isText {
                            Text(content.content ?? "")
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.badge.gearshape")
                                    .font(.system(size: 28, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("Binary file")
                                    .font(.system(size: 12, weight: .medium))
                                Text("\(content.mime) · \(Fmt.bytes(content.size))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 34)
                        }

                        if content.truncated {
                            Text("Showing the first \(Fmt.bytes(content.maxBytes)) of \(Fmt.bytes(content.size)).")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.warn)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 10)
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Back to folder")
            .accessibilityLabel("Back to folder")

            VStack(alignment: .leading, spacing: 1) {
                Text(content?.name ?? (path as NSString).lastPathComponent)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }

            if let content {
                Text("\(Fmt.bytes(content.size))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(Fmt.relative(from: content.modifiedDate))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy path")

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Reveal in Finder")

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open in default app")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func load() async {
        if state.api == nil { await state.bootstrap() }
        guard let api = state.api else {
            error = "The hub is not connected."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.hostFileContent(path: path)
            content = result
            error = nil
            if result.isImage {
                let data = try await api.hostFileData(path: path)
                image = NSImage(data: data)
                if image == nil {
                    error = "The image could not be decoded."
                }
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
