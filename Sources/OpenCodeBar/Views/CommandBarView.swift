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
        didSet {
            if agentError != nil { agentError = nil }
            applyRanking()
        }
    }
    @Published private(set) var sections: [CommandSection] = []
    @Published private(set) var selectedID: String?
    @Published private(set) var mention: CommandMentionState?
    @Published private(set) var isSendingToAgent = false
    @Published private(set) var agentError: String?

    private weak var state: AppState?
    private var items: [CommandItem] = []
    private var mentionEditor: CommandMentionEditor?
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
        if let mention {
            updateMention(
                CommandMentionContext(query: mention.query, range: mention.range)
            )
        }
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

    var canAskAgent: Bool {
        mention == nil
            && !isSendingToAgent
            && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var shouldOfferAgent: Bool {
        isSendingToAgent || agentError != nil
            || (mention == nil && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func moveSelection(by delta: Int) {
        if mention != nil {
            moveMentionSelection(by: delta)
            return
        }

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
        if mention != nil {
            activateMentionSelection()
            return
        }
        guard let selectedItem else { return }
        activate(selectedItem)
    }

    func toggleFavorite(_ item: CommandItem) {
        favorites.toggle(item.id)
        selectedID = item.id
        rebuild()
    }

    // MARK: Mentions

    func attachMentionEditor(_ editor: CommandMentionEditor) {
        mentionEditor = editor
    }

    /// Called by the editor whenever the `@` token or the caret moves.
    func updateMention(_ context: CommandMentionContext?) {
        guard let context else {
            if mention != nil { mention = nil }
            return
        }

        let sections = CommandMentionPalette.sections(items: items, query: context.query)
        guard !sections.isEmpty else {
            if mention != nil { mention = nil }
            return
        }

        let all = sections.flatMap(\.items)
        let kept = mention?.selectedID.flatMap { id in
            all.contains(where: { $0.id == id }) ? id : nil
        }
        let next = CommandMentionState(
            query: context.query,
            range: context.range,
            sections: sections,
            selectedID: kept ?? all.first?.id
        )
        if next != mention { mention = next }
    }

    func moveMentionSelection(by delta: Int) {
        guard var current = mention else { return }
        let all = current.items
        guard !all.isEmpty else { return }

        if let index = all.firstIndex(where: { $0.id == current.selectedID }) {
            let next = ((index + delta) % all.count + all.count) % all.count
            current.selectedID = all[next].id
        } else {
            current.selectedID = delta >= 0 ? all.first?.id : all.last?.id
        }
        mention = current
    }

    func activateMentionSelection() {
        guard let item = mention?.selectedItem else { return }
        activateMention(item)
    }

    func activateMention(_ item: CommandItem) {
        mention = nil
        mentionEditor?.insert(item)
        mentionEditor?.focus()
    }

    func clearMention() {
        if mention != nil { mention = nil }
    }

    // MARK: Agent

    /// Sends the command-bar text to the OpenCode agent instead of opening a
    /// result. The agent can use the opencodebar MCP tools for project and
    /// session actions.
    func sendToAgent() {
        guard let state, canAskAgent else { return }
        let prompt = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        isSendingToAgent = true
        agentError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let session = try await state.runCommandBarPrompt(prompt)
                isSendingToAgent = false
                state.isCommandBarPresented = false
                state.tab = .tasks
                state.open(session)
            } catch {
                isSendingToAgent = false
                agentError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
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

    @State private var focusRequest = 0
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
            if model.mention != nil {
                mentionDropdown
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            Divider().opacity(0.55)
            results
            Divider().opacity(0.55)
            footer
        }
        .animation(.easeOut(duration: 0.12), value: model.mention != nil)
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
            Image(systemName: model.mention != nil ? "at" : "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    model.mention != nil || model.isSearching ? Theme.accent : Color.secondary
                )

            ZStack(alignment: .leading) {
                if model.query.isEmpty {
                    Text("Search, or type @ to reference…")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }

                CommandMentionField(
                    text: $model.query,
                    focusRequest: focusRequest,
                    onMentionChange: { model.updateMention($0) },
                    onEditorReady: { model.attachMentionEditor($0) }
                )
                .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
            }
            .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24, alignment: .leading)

            if !model.query.isEmpty {
                Button {
                    model.clearMention()
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

    private var mentionDropdown: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let mention = model.mention {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(mention.sections) { section in
                                VStack(alignment: .leading, spacing: 1) {
                                    sectionHeader(section)
                                    ForEach(section.items) { item in
                                        MentionOptionRow(
                                            item: item,
                                            state: state,
                                            isSelected: mention.selectedID == item.id
                                        ) {
                                            model.activateMention(item)
                                        }
                                        .id(item.id)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: mention.selectedID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.10)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            HStack(spacing: 8) {
                KeyHint(keys: "↑↓", label: "Choose reference")
                KeyHint(keys: "↵", label: "Insert")
                Spacer(minLength: 0)
                Text("Projects, sessions, tabs, apps, terminals, devices")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.shouldOfferAgent {
                        CommandAgentRow(
                            isSending: model.isSendingToAgent,
                            error: model.agentError
                        ) {
                            model.sendToAgent()
                        }
                    }

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
                    ? "Try a project name, session title, path, app, terminal, or setting. Type @ to reference one."
                    : "Projects, sessions, apps, terminals, devices, and navigation in one place. Type @ to reference one."
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
            KeyHint(keys: "⌘↵", label: "Ask agent")
            KeyHint(keys: "esc", label: "Close")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: Keyboard

    private func focusSearch() {
        focusRequest &+= 1
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

            // Never steal keys while an input method is composing a character.
            if !event.modifierFlags.contains(.command),
               let editor = windowRef.window?.firstResponder as? NSTextView,
               editor.hasMarkedText() {
                return event
            }

            let command = event.modifierFlags.contains(.command)
            let character = event.charactersIgnoringModifiers?.lowercased()

            if command, event.keyCode == 36 || event.keyCode == 76 {
                model.sendToAgent()
                return nil
            }
            if command, character == "k" {
                dismiss()
                return nil
            }
            if command, character == "d" {
                if model.mention == nil, let item = model.selectedItem {
                    model.toggleFavorite(item)
                }
                return nil
            }
            if event.keyCode == 53 {
                if model.mention != nil {
                    model.clearMention()
                } else {
                    dismiss()
                }
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

// MARK: - Agent row

@MainActor
private struct CommandAgentRow: View {
    let isSending: Bool
    let error: String?
    let onSend: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSend) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.reasoning.opacity(0.14))
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.reasoning)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask agent")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(
                        error
                            ?? (isSending
                                ? "Sending to OpenCode…"
                                : "Send this command with its @ references")
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(error == nil ? Color.secondary : Theme.danger)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 4)

                if isSending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    KeyCap(key: "⌘↵")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        isHovering
                            ? Theme.reasoning.opacity(0.12)
                            : Theme.reasoning.opacity(0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Theme.reasoning.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .onHover { hovering in isHovering = hovering }
    }
}

// MARK: - Mention row

@MainActor
private struct MentionOptionRow: View {
    let item: CommandItem
    let state: AppState
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            icon

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if let badge = item.badge {
                Chip(text: badge, tint: item.badgeTint.color)
            }

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Theme.accent.opacity(0.13))
                    )
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Theme.accent.opacity(0.13)
                        : (isHovering ? Color.primary.opacity(0.045) : Color.clear)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering in isHovering = hovering }
        .animation(.easeOut(duration: 0.10), value: isSelected)
    }

    @ViewBuilder
    private var icon: some View {
        switch item.icon {
        case .project(let id):
            ProjectIconView(
                image: state.projectIcons[id],
                running: item.isRunning,
                size: 22
            )

        case .app(let path, let hasIcon):
            AppIconView(api: state.api, path: path, hasIcon: hasIcon, size: 18)
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(item.tint.color.opacity(0.10))
                )

        case .symbol(let name):
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(item.tint.color.opacity(0.14))
                Image(systemName: name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.tint.color)
            }
            .frame(width: 22, height: 22)
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
