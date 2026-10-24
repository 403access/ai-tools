import SwiftUI
import UIKit

/// Read-only browser for the Mac running the hub, opened from the System tab.
struct MobileFileBrowserView: View {
    @EnvironmentObject private var store: MobileStore

    @State private var path: String
    @State private var listing: HostDirectory?
    @State private var isLoading = false
    @State private var error: String?
    @State private var query = ""
    @State private var showHidden = false

    init(startPath: String) {
        _path = State(initialValue: startPath)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                breadcrumbs
                quickRoots
                searchField

                if let error {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                }

                if isLoading && listing == nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Reading folder…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                } else if let listing {
                    entriesCard(listing)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .mobileScreenBackground()
        .navigationTitle(listing?.name ?? (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showHidden.toggle()
                    } label: {
                        Image(systemName: showHidden ? "eye" : "eye.slash")
                    }
                    .accessibilityLabel(showHidden ? "Hide hidden files" : "Show hidden files")

                    Button {
                        Task { await load(path) }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Reload folder")
                }
            }
        }
        .refreshable { await load(path) }
        .task(id: path) { await load(path) }
    }

    // MARK: - Navigation

    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(crumbs, id: \.path) { crumb in
                    Button {
                        navigate(to: crumb.path)
                    } label: {
                        HStack(spacing: 3) {
                            if crumb.isRoot {
                                Image(systemName: "internaldrive")
                                    .font(.system(size: 8, weight: .semibold))
                            }
                            Text(crumb.name)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(crumb.path == path ? Theme.accent : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                crumb.path == path
                                    ? Theme.accent.opacity(0.13)
                                    : Color.primary.opacity(0.045)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var quickRoots: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(quickRootsList) { root in
                    Button {
                        navigate(to: root.path)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: root.icon)
                                .font(.caption2.weight(.semibold))
                            Text(root.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(root.path == path ? Theme.accent : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(
                                root.path == path
                                    ? Theme.accent.opacity(0.13)
                                    : Color.primary.opacity(0.05)
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            TextField("Filter this folder", text: $query)
                .textFieldStyle(.plain)
                .font(.caption)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
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
                    HStack(spacing: 9) {
                        Image(systemName: "arrow.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Parent folder")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(parent)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }

            if entries.isEmpty {
                Text(emptyLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if entry.isDirectory {
                            Button {
                                navigate(to: entry.path)
                            } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink {
                                MobileFilePreviewView(path: entry.path)
                            } label: {
                                entryRow(entry)
                            }
                            .buttonStyle(.plain)
                        }
                        if index != entries.count - 1 {
                            Divider().opacity(0.22)
                        }
                    }
                }
            }

            if listing.truncated {
                Divider().opacity(0.3)
                Text("Showing the first \(listing.entries.count) of \(Fmt.grouped(listing.total)) entries.")
                    .font(.caption2)
                    .foregroundStyle(Theme.warn)
                    .padding(.top, 8)
            }
        }
        .card(padding: 10)
    }

    private func entryRow(_ entry: HostFileEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: entry.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(entry.isDirectory ? Theme.accent : entry.kind == "symlink" ? Theme.reasoning : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.name)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(entry.hidden ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.kind == "symlink" {
                        Image(systemName: "link")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.reasoning)
                    }
                }
                if let target = entry.linkTarget {
                    Text(target)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let date = entry.modifiedDate {
                    Text(Fmt.relative(from: date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            if let size = entry.size, !entry.isDirectory {
                Text(Fmt.bytes(size))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Image(systemName: entry.isDirectory ? "chevron.right" : "doc.text.magnifyingglass")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 8)
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
        if trimmed == path {
            Task { await load(trimmed) }
        } else {
            path = trimmed
        }
    }

    private func load(_ target: String) async {
        guard let api = store.api else {
            error = "The hub is not connected."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await api.hostFiles(path: target)
            listing = result
            if result.path != path {
                path = result.path
            }
            error = nil
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private var crumbs: [MobileCrumb] {
        if path.contains("\\") {
            let parts = path.split(separator: "\\", omittingEmptySubsequences: true)
            var result: [MobileCrumb] = []
            var current = ""
            for (index, part) in parts.enumerated() {
                current = index == 0 ? "\(part)\\" : "\(current)\(part)\\"
                result.append(MobileCrumb(name: String(part), path: current, isRoot: index == 0))
            }
            return result
        }

        var result = [MobileCrumb(name: "/", path: "/", isRoot: true)]
        var current = ""
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            current += "/\(part)"
            result.append(MobileCrumb(name: String(part), path: current, isRoot: false))
        }
        return result
    }

    private var quickRootsList: [HostFileRoot] {
        var values = listing?.roots ?? []
        for project in store.orderedProjects.prefix(10) {
            values.append(HostFileRoot(name: project.displayName, path: project.canonical, kind: "project"))
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.path).inserted }
    }
}

private struct MobileCrumb {
    let name: String
    let path: String
    let isRoot: Bool
}

// MARK: - Preview

struct MobileFilePreviewView: View {
    @EnvironmentObject private var store: MobileStore

    let path: String

    @State private var content: HostFileContent?
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            Group {
                if isLoading && content == nil {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Reading file…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else if let error {
                    NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
                        .padding(16)
                } else if let content {
                    VStack(alignment: .leading, spacing: 12) {
                        if content.isImage, let image {
                            Image(uiImage: image)
                                .resizable()
                                .interpolation(.high)
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .card(padding: 8)
                        } else if content.isText {
                            Text(content.content ?? "")
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .card(padding: 0)
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "doc.badge.gearshape")
                                    .font(.system(size: 38, weight: .light))
                                    .foregroundStyle(.tertiary)
                                Text("Binary file")
                                    .font(.headline)
                                Text("\(content.mime) · \(Fmt.bytes(content.size))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                            .card()
                        }

                        if content.truncated {
                            NoticeRow(
                                icon: "scissors",
                                message: "Showing the first \(Fmt.bytes(content.maxBytes)) of \(Fmt.bytes(content.size)).",
                                tint: Theme.warn
                            )
                        }

                        HStack(spacing: 12) {
                            Text(content.mime)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text(Fmt.bytes(content.size))
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text(Fmt.relative(from: content.modifiedDate))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
        .mobileScreenBackground()
        .navigationTitle(content?.name ?? (path as NSString).lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = path
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy path")
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let api = store.api else {
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
                image = UIImage(data: data)
                if image == nil {
                    error = "The image could not be decoded."
                }
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
