import AppKit
import SwiftUI

/// The project's Structure tab. Builds the layered map once per file payload,
/// so the diagram and the Files tab always describe the same checkout.
struct ProjectStructureTab: View {
    let projectName: String
    let projectPath: String
    let files: ProjectFiles
    let loadedAt: Date?

    @StateObject private var cache = ProjectStructureCache()

    private var buildKey: String {
        let stamp = loadedAt?.timeIntervalSince1970 ?? 0
        return "\(files.total)|\(files.changed)|\(files.files.count)|\(files.truncated)|\(stamp)"
    }

    var body: some View {
        // The cache keeps live project updates from rebuilding the map on every
        // body pass; it only recomputes when the file payload actually changes.
        let structure = cache.structure(
            name: projectName,
            files: files,
            key: buildKey
        )

        return Group {
            if let structure {
                ProjectStructureView(
                    structure: structure,
                    projectName: projectName,
                    projectPath: projectPath
                )
            } else if files.files.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Structure")
                    EmptyState(
                        icon: "square.3.layers.3d",
                        title: "Nothing to map",
                        subtitle: "This project folder has no files to draw yet."
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader("Structure")
                    LoadingState(message: "Mapping project folders…")
                }
            }
        }
    }
}

/// One-entry memo for the structure map, owned by the tab so live project
/// updates do not re-scan the same file payload on every body pass.
@MainActor
private final class ProjectStructureCache: ObservableObject {
    private var key: String?
    private var value: ProjectStructure?

    func structure(name: String, files: ProjectFiles, key: String) -> ProjectStructure? {
        if key == self.key {
            return value
        }
        let built = ProjectStructureBuilder.build(name: name, project: files)
        self.key = key
        self.value = built
        return built
    }
}

/// A technical, left-to-right diagram of the project folder: root, top-level
/// areas, modules, and nested folders. Connections mean containment. Selecting
/// a node keeps its path and language mix one click away.
struct ProjectStructureView: View {
    let structure: ProjectStructure
    let projectName: String
    let projectPath: String

    @State private var selectedID: String?

    private var layout: ProjectStructureLayout {
        ProjectStructureLayout(structure: structure)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summary
            diagram
            if let selected = selectedID.flatMap({ structure.node($0) }) {
                selectionCard(selected)
            }
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Project structure")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 4)
                Chip(
                    text: "\(structure.columns.count) layers",
                    systemImage: "square.stack.3d.up",
                    tint: Theme.reasoning
                )
            }

            HStack(spacing: 0) {
                metric("Files", Fmt.grouped(structure.totalFiles))
                metricDivider
                metric("Folders", Fmt.grouped(structure.totalFolders))
                metricDivider
                metric("Nodes", "\(structure.nodes.count)")
                metricDivider
                metric("Links", "\(structure.edges.count)")
                metricDivider
                metric(
                    "Changed",
                    Fmt.grouped(structure.changedFiles),
                    tint: structure.changedFiles > 0 ? Theme.warn : nil
                )
            }

            languageBar
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private func metric(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint ?? .primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var languageBar: some View {
        let total = max(structure.languages.reduce(0) { $0 + $1.files }, 1)
        let shown = Array(structure.languages.prefix(6))
        let shownFiles = shown.reduce(0) { $0 + $1.files }
        let otherFiles = max(total - shownFiles, 0)

        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                GeometryReader { geometry in
                    HStack(spacing: 1.5) {
                        ForEach(shown) { language in
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(ProjectStructureStyle.tint(for: language.name))
                                .frame(
                                    width: max(
                                        CGFloat(language.files) / CGFloat(total) * geometry.size.width,
                                        language.files > 0 ? 2 : 0
                                    )
                                )
                        }
                        if otherFiles > 0 {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.primary.opacity(0.12))
                                .frame(
                                    width: max(
                                        CGFloat(otherFiles) / CGFloat(total) * geometry.size.width,
                                        2
                                    )
                                )
                        }
                    }
                }
                .frame(height: 4)

                HStack(spacing: 9) {
                    ForEach(shown.prefix(5)) { language in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(ProjectStructureStyle.tint(for: language.name))
                                .frame(width: 5, height: 5)
                            Text(language.name)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .help("\(Fmt.grouped(language.files)) files")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Diagram

    private var diagram: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Map") {
                Text("\(structure.nodes.count) nodes · \(structure.edges.count) links")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    columnHeaders
                    canvas
                }
                .padding(8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.025))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
            )

            Text(
                structure.truncated
                    ? "Columns show the largest folders; +N on a node counts the hidden children."
                    : "Edges show containment. Select a node to read its path and file mix."
            )
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private var columnHeaders: some View {
        HStack(alignment: .bottom, spacing: ProjectStructureLayout.columnGap) {
            ForEach(Array(structure.columns.enumerated()), id: \.offset) { index, ids in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(columnTitle(index).uppercased())
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 2)
                        Text("\(ids.count)")
                            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Rectangle()
                        .fill(depthTint(index).opacity(0.55))
                        .frame(height: 1)
                }
                .frame(width: ProjectStructureLayout.nodeWidth, alignment: .leading)
            }
        }
        .padding(.horizontal, ProjectStructureLayout.padding)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.018))

            dotGrid

            edgeCanvas

            ForEach(layout.items) { item in
                nodeButton(item.node)
                    .offset(x: item.frame.minX, y: item.frame.minY)
            }
        }
        .frame(
            width: layout.size.width,
            height: layout.size.height,
            alignment: .topLeading
        )
    }

    private var dotGrid: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 16
            var x: CGFloat = 8
            while x < size.width {
                var y: CGFloat = 8
                while y < size.height {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.1, height: 1.1))
                    y += spacing
                }
                x += spacing
            }
            context.fill(path, with: .color(Color.primary.opacity(0.09)))
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
    }

    private var edgeCanvas: some View {
        let frames = layout.frames
        let selected = selectedID

        return Canvas { context, _ in
            let plain = Color.primary.opacity(0.17)
            let highlighted = Theme.accent.opacity(0.85)

            for pass in 0 ..< 2 {
                for edge in structure.edges {
                    let isHighlighted = selected.map {
                        edge.parentID == $0 || edge.childID == $0
                    } ?? false
                    guard isHighlighted == (pass == 1) else { continue }
                    guard let parent = frames[edge.parentID],
                          let child = frames[edge.childID] else { continue }

                    var path = Path()
                    let start = CGPoint(x: parent.maxX, y: parent.midY)
                    let end = CGPoint(x: child.minX, y: child.midY)
                    let controlX = start.x + (end.x - start.x) * 0.5
                    path.move(to: start)
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: controlX, y: start.y),
                        control2: CGPoint(x: controlX, y: end.y)
                    )
                    context.stroke(
                        path,
                        with: .color(isHighlighted ? highlighted : plain),
                        lineWidth: isHighlighted ? 1.5 : 1
                    )

                    if isHighlighted {
                        context.fill(
                            Path(ellipseIn: CGRect(
                                x: end.x - 2,
                                y: end.y - 2,
                                width: 4,
                                height: 4
                            )),
                            with: .color(highlighted)
                        )
                    }
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .allowsHitTesting(false)
    }

    private func nodeButton(_ node: ProjectStructure.Node) -> some View {
        let isSelected = selectedID == node.id
        let tint = ProjectStructureStyle.tint(for: node.primaryLanguage?.name)

        return Button {
            selectedID = isSelected ? nil : node.id
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(tint)
                        .frame(width: 5.5, height: 5.5)
                    Text(node.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 2)
                    if node.hiddenChildren > 0 {
                        Text("+\(node.hiddenChildren)")
                            .font(.system(size: 8, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 4) {
                    Text(node.isFile ? "file" : "\(Fmt.grouped(node.fileCount)) files")
                    if let language = node.primaryLanguage {
                        Text("·")
                        Text(language.name)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 2)
                    if node.changedCount > 0 {
                        Image(systemName: "pencil")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Theme.warn)
                        Text("\(node.changedCount)")
                            .font(.system(size: 8, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.warn)
                    }
                }
                .font(.system(size: 8.5))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .frame(
                width: ProjectStructureLayout.nodeWidth,
                height: ProjectStructureLayout.nodeHeight,
                alignment: .leading
            )
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isSelected ? 0.10 : 0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.07),
                        lineWidth: isSelected ? 1.2 : 1
                    )
            )
            .shadow(color: isSelected ? Theme.accent.opacity(0.16) : .clear, radius: 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip(for: node))
        .accessibilityLabel(tooltip(for: node))
    }

    private func tooltip(for node: ProjectStructure.Node) -> String {
        var lines = [node.path.isEmpty ? projectName : node.path]
        lines.append(
            node.isFile
                ? (node.primaryLanguage?.name ?? "File")
                : "\(Fmt.grouped(node.fileCount)) files"
        )
        if let primary = node.primaryLanguage {
            let names = [primary.name] + node.languages.dropFirst().map(\.name)
            lines.append(
                (names + ["\(Fmt.grouped(primary.files)) files"]).joined(separator: " · ")
            )
        }
        if node.changedCount > 0 {
            lines.append("\(node.changedCount) changed in the working tree")
        }
        if node.hiddenChildren > 0 {
            lines.append("\(node.hiddenChildren) nested folders not drawn")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Selection

    private func selectionCard(_ node: ProjectStructure.Node) -> some View {
        let tint = ProjectStructureStyle.tint(for: node.primaryLanguage?.name)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                Text(node.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    reveal(node)
                } label: {
                    Text("Reveal")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                Button {
                    selectedID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear selection")
            }

            Text(node.path.isEmpty ? projectName : node.path)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)

            HStack(spacing: 5) {
                Chip(
                    text: node.isFile ? "File" : "\(Fmt.grouped(node.fileCount)) files",
                    systemImage: node.isFile ? "doc.text" : "folder.fill"
                )
                if node.changedCount > 0 {
                    Chip(
                        text: "\(node.changedCount) changed",
                        systemImage: "pencil",
                        tint: Theme.warn
                    )
                }
                if node.hiddenChildren > 0 {
                    Chip(
                        text: "+\(node.hiddenChildren) nested",
                        systemImage: "square.stack.3d.down.right"
                    )
                }
                Spacer(minLength: 0)
            }

            if !node.languages.isEmpty {
                HStack(spacing: 5) {
                    ForEach(node.languages) { language in
                        Chip(
                            text: "\(language.name) \(language.files)",
                            tint: ProjectStructureStyle.tint(for: language.name)
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 9)
    }

    private func reveal(_ node: ProjectStructure.Node) {
        let base = URL(fileURLWithPath: projectPath, isDirectory: true)
        let url = node.path.isEmpty
            ? base
            : base.appendingPathComponent(node.path)
        if node.isFile {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Depth labels

    private func columnTitle(_ depth: Int) -> String {
        switch depth {
        case 0: return "Root"
        case 1: return "Areas"
        case 2: return "Modules"
        default: return "Nested"
        }
    }

    private func depthTint(_ depth: Int) -> Color {
        switch depth {
        case 0: return Theme.accent
        case 1: return Theme.running
        case 2: return Theme.reasoning
        default: return Theme.warn
        }
    }
}

// MARK: - Layout

/// Deterministic geometry for the diagram. Nodes stack in columns; each parent
/// is pulled toward the average of its children, then pushed down if that would
/// overlap the node above it. Because the frames are computed up front, the
/// Canvas edges and the SwiftUI nodes cannot drift apart.
struct ProjectStructureLayout {
    struct Item: Identifiable {
        let node: ProjectStructure.Node
        let frame: CGRect

        var id: String { node.id }
    }

    static let nodeWidth: CGFloat = 176
    static let nodeHeight: CGFloat = 44
    static let columnGap: CGFloat = 34
    static let rowGap: CGFloat = 11
    static let padding: CGFloat = 4

    let items: [Item]
    let frames: [String: CGRect]
    let size: CGSize

    init(structure: ProjectStructure) {
        var centers: [String: CGFloat] = [:]
        let childrenByParent = Dictionary(grouping: structure.edges, by: \.parentID)

        // Place the deepest column first, then work back toward the root. Each
        // column is normalized so its first node sits at the top; otherwise a
        // parent centered on a low child would drag the whole map down.
        if !structure.columns.isEmpty {
            for depth in stride(from: structure.columns.count - 1, through: 0, by: -1) {
                var previousBottom = -Self.rowGap
                var column: [(id: String, center: CGFloat)] = []

                for id in structure.columns[depth] {
                    let childCenters = (childrenByParent[id] ?? [])
                        .compactMap { centers[$0.childID] }
                    let minimum = previousBottom + Self.rowGap + Self.nodeHeight / 2
                    let desired = childCenters.isEmpty
                        ? minimum
                        : childCenters.reduce(0, +) / CGFloat(childCenters.count)
                    let center = max(desired, minimum)
                    column.append((id, center))
                    previousBottom = center + Self.nodeHeight / 2
                }

                if let first = column.first {
                    let shift = Self.nodeHeight / 2 - first.center
                    for entry in column {
                        centers[entry.id] = entry.center + shift
                    }
                }
            }
        }

        var frames: [String: CGRect] = [:]
        var items: [Item] = []
        for (depth, ids) in structure.columns.enumerated() {
            let x = Self.padding + CGFloat(depth) * (Self.nodeWidth + Self.columnGap)
            for id in ids {
                guard let center = centers[id],
                      let node = structure.node(id) else { continue }
                let frame = CGRect(
                    x: x,
                    y: Self.padding + center - Self.nodeHeight / 2,
                    width: Self.nodeWidth,
                    height: Self.nodeHeight
                )
                frames[id] = frame
                items.append(Item(node: node, frame: frame))
            }
        }

        let width = (frames.values.map(\.maxX).max() ?? 0) + Self.padding
        let height = (frames.values.map(\.maxY).max() ?? 0) + Self.padding
        self.items = items
        self.frames = frames
        self.size = CGSize(width: max(width, Self.nodeWidth + 2 * Self.padding), height: height)
    }
}

// MARK: - Palette

enum ProjectStructureStyle {
    static func tint(for language: String?) -> Color {
        switch language {
        case "Swift": return Theme.accent
        case "TypeScript", "JavaScript", "Vue", "Svelte", "Go": return Theme.running
        case "Nix", "Make", "Just", "Docker": return Theme.reasoning
        case "Shell", "Kotlin", "Java", "C#": return Theme.warn
        case "CSS", "HTML", "Rust": return Theme.cacheWrite
        case "Python", "Ruby", "PHP", "Lua", "Elixir", "Dart": return Theme.cacheRead
        case "Markdown", "Text", "Asset": return .secondary
        case "JSON", "YAML", "TOML", "XML", "Config", "SQL", "CSV": return Theme.input
        default: return Theme.output
        }
    }
}
