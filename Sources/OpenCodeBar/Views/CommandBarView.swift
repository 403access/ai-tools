import AppKit
import Combine
import SwiftUI

// MARK: - Favorites

/// User-pinned command-bar results. The newest favorite sits first so the
/// section doubles as a most-recently-pinned list.
@MainActor
final class CommandFavorites: ObservableObject {
    static let shared = CommandFavorites()

    private static let defaultsKey = "commandBar.favoriteIDs"

    @Published private(set) var ids: [String]

    private init() {
        ids = UserDefaults.standard.stringArray(forKey: Self.defaultsKey) ?? []
    }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    func toggle(_ id: String) {
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.insert(id, at: 0)
        }
        UserDefaults.standard.set(ids, forKey: Self.defaultsKey)
    }
}

// MARK: - Model

/// Owns the query, the ranked sections and the keyboard selection. It follows
/// `AppState` so live renames, new sessions and a changed running set appear
/// while the palette is open.
@MainActor
final class CommandPaletteModel: ObservableObject {
    @Published var query = "" {
        didSet { applyRanking() }
    }
    @Published private(set) var sections: [CommandSection] = []
    @Published private(set) var selectedID: String?

    private weak var state: AppState?
    private var items: [CommandItem] = []
    private let favorites = CommandFavorites.shared
    private var cancellables: Set<AnyCancellable> = []
    private var attached = false

    func attach(_ state: AppState) {
        guard !attached else {
            rebuild()
            return
        }
        attached = true
        self.state = state

        // objectWillChange fires before the mutation, so rebuild on the next
        // run-loop turn to read the new sessions, projects or system snapshot.
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        favorites.$ids
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        rebuild()
    }

    func rebuild() {
        guard let state else { return }
        let next = state.commandBarItems()
        if next != items {
            items = next
        }
        applyRanking()
    }

    var allItems: [CommandItem] {
        sections.flatMap(\.items)
    }

    var selectedItem: CommandItem? {
        allItems.first { $0.id == selectedID }
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var resultCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    func moveSelection(by delta: Int) {
        let all = allItems
        guard !all.isEmpty else { return }

        guard let current = all.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = delta >= 0 ? all.first?.id : all.last?.id
            return
        }

        let count = all.count
        let next = ((current + delta) % count + count) % count
        selectedID = all[next].id
    }

    func activate(_ item: CommandItem) {
        guard let state else { return }
        state.performCommand(item.action)
        state.isCommandBarPresented = false
    }

    func activateSelected() {
        guard let selectedItem else { return }
        activate(selectedItem)
    }

    func toggleFavorite(_ item: CommandItem) {
        favorites.toggle(item.id)
        selectedID = item.id
        rebuild()
    }

    private func applyRanking() {
        let ranked = CommandPalette.sections(
            items: items,
            favoriteIDs: favorites.ids,
            query: query
        )
        if ranked != sections {
            sections = ranked
        }

        let all = ranked.flatMap(\.items)
        if let selectedID, all.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = all.first?.id
    }
}

// MARK: - Overlay

/// The command bar itself. It is hosted above whichever surface is open: the
/// desktop window or the compact menu bar panel.
@MainActor
struct CommandBarOverlay: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var model = CommandPaletteModel()
    @ObservedObject private var favorites = CommandFavorites.shared

    @FocusState private var searchFocused: Bool
    @State private var windowRef = CommandWindowRef()
    @State private var keyMonitor: Any?
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { proxy in
            let width = min(max(proxy.size.width - 32, 320), 680)
            let height = min(max(proxy.size.height - 48, 360), 580)
            let top = max(min((proxy.size.height - height) * 0.18, 64), 12)

            ZStack(alignment: .top) {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .onTapGesture { dismiss() }

                card
                    .frame(width: width, height: height)
                    .padding(.top, top)
                    .scaleEffect(hasAppeared ? 1 : 0.975, anchor: .top)
                    .opacity(hasAppeared ? 1 : 0)
            }
        }
        .background(
            WindowProbe { windowRef.window = $0 }
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .onAppear {
            model.attach(state)
            installKeyMonitor()
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                hasAppeared = true
            }
            focusSearch()
            Task { await state.prepareCommandBarSearch() }
        }
        .onDisappear {
            removeKeyMonitor()
            hasAppeared = false
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().opacity(0.55)
            results
            Divider().opacity(0.55)
            footer
        }
        .background(
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(
                    colors: [Theme.accent.opacity(0.10), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Theme.accent.opacity(0.22),
                            Color.black.opacity(0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.28), radius: 42, y: 18)
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(model.isSearching ? Theme.accent : Color.secondary)

            TextField(
                "",
                text: $model.query,
                prompt: Text("Search projects, sessions, apps, settings…")
                    .foregroundStyle(.secondary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .medium))
            .focused($searchFocused)
            .onSubmit { model.activateSelected() }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    focusSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            KeyCap(key: "esc")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.sections.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.sections) { section in
                            VStack(alignment: .leading, spacing: 3) {
                                sectionHeader(section)
                                ForEach(section.items) { item in
                                    CommandResultRow(
                                        item: item,
                                        state: state,
                                        isSelected: model.selectedID == item.id,
                                        isFavorite: favorites.contains(item.id),
                                        onOpen: { model.activate(item) },
                                        onToggleFavorite: { model.toggleFavorite(item) }
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ section: CommandSection) -> some View {
        HStack(spacing: 6) {
            Image(systemName: section.icon)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(section.kind == .favorites ? Theme.warn : Color.secondary)
            Text(section.title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text("\(section.items.count)")
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 9)
        .padding(.top, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.isSearching ? "magnifyingglass" : "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)

            Text(model.isSearching ? "No results for “\(model.query)”" : "Search everything")
                .font(.system(size: 13, weight: .semibold))

            Text(
                model.isSearching
                    ? "Try a project name, session title, path, app, terminal, or setting."
                    : "Projects, sessions, apps, terminals, devices, and navigation in one place."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 52)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(model.resultCount) result\(model.resultCount == 1 ? "" : "s")")
                .font(.system(size: 9, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            KeyHint(keys: "↑↓", label: "Navigate")
            KeyHint(keys: "↵", label: "Open")
            KeyHint(keys: "⌘D", label: "Favorite")
            KeyHint(keys: "esc", label: "Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Keyboard

    private func focusSearch() {
        searchFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            searchFocused = true
        }
    }

    private func dismiss() {
        state.isCommandBarPresented = false
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard state.isCommandBarPresented else { return event }
            if let window = windowRef.window,
               let eventWindow = event.window,
               eventWindow !== window {
                return event
            }

            let command = event.modifierFlags.contains(.command)
            let character = event.charactersIgnoringModifiers?.lowercased()

            if command, character == "k" {
                dismiss()
                return nil
            }
            if command, character == "d" {
                if let item = model.selectedItem {
                    model.toggleFavorite(item)
                }
                return nil
            }
            if event.keyCode == 53 {
                dismiss()
                return nil
            }

            switch event.keyCode {
            case 126:
                model.moveSelection(by: -1)
                return nil
            case 125:
                model.moveSelection(by: 1)
                return nil
            case 36, 76:
                model.activateSelected()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}

// MARK: - Result row

@MainActor
private struct CommandResultRow: View {
    let item: CommandItem
    let state: AppState
    let isSelected: Bool
    let isFavorite: Bool
    let onOpen: () -> Void
    let onToggleFavorite: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let badge = item.badge {
                        Chip(text: badge, tint: item.badgeTint.color)
                    }
                }

                Text(item.subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 20, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.accent.opacity(0.13))
                    )
                    .help("Open")
            }

            Button(action: onToggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        isFavorite
                            ? Theme.warn
                            : (isHovering || isSelected ? Color.secondary : Color.clear)
                    )
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isFavorite ? "Remove from favorites (⌘D)" : "Add to favorites (⌘D)")
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? Theme.accent.opacity(0.13)
                        : (isHovering ? Color.primary.opacity(0.045) : Color.clear)
                )
        )
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 2.5, height: 21)
                    .offset(x: -1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering in
            isHovering = hovering
        }
        .animation(.easeOut(duration: 0.10), value: isSelected)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .project(let id):
            ProjectIconView(
                image: state.projectIcons[id],
                running: item.isRunning,
                size: 30
            )

        case .app(let path, let hasIcon):
            AppIconView(api: state.api, path: path, hasIcon: hasIcon, size: 26)
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.tint.color.opacity(0.10))
                )

        case .symbol(let name):
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(item.tint.color.opacity(0.14))
                Image(systemName: name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.tint.color)
            }
            .frame(width: 30, height: 30)
        }
    }
}

// MARK: - Chrome

private struct KeyCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(keys)
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                )
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

extension CommandTint {
    var color: Color {
        switch self {
        case .accent: return Theme.accent
        case .running: return Theme.running
        case .warning: return Theme.warn
        case .danger: return Theme.danger
        case .secondary: return .secondary
        case .reasoning: return Theme.reasoning
        }
    }
}

// MARK: - Host

/// Adds the command bar above a surface and animates it in and out. Both the
/// desktop window and the compact panel call this, so ⌘K behaves the same
/// wherever the app is open.
struct CommandBarHost: ViewModifier {
    @EnvironmentObject private var state: AppState

    func body(content: Content) -> some View {
        ZStack {
            content

            if state.isCommandBarPresented {
                CommandBarOverlay()
                    .zIndex(100)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: state.isCommandBarPresented)
    }
}

extension View {
    func commandBarHost() -> some View {
        modifier(CommandBarHost())
    }
}

// MARK: - Window probe

private final class CommandWindowRef {
    weak var window: NSWindow?
}

private struct WindowProbe: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ProbeView)?.onChange = onChange
    }

    private final class ProbeView: NSView {
        var onChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange?(window)
        }
    }
}
