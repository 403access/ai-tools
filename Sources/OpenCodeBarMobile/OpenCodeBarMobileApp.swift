import SwiftUI

@main
struct OpenCodeBarMobileApp: App {
    @StateObject private var settings: HubSettingsStore
    @StateObject private var store: MobileStore
    @StateObject private var appearance: AppearanceStore
    @StateObject private var router = MobileRouter()

    init() {
        let settings = HubSettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: MobileStore(settings: settings))
        _appearance = StateObject(wrappedValue: AppearanceStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(appearance)
                .environmentObject(router)
                .tint(Theme.accent)
                .preferredColorScheme(appearance.appearance.colorScheme)
        }
    }
}

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case tasks
        case live
        case projects
        case usage
        case host
        case vms
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tasks: return "Tasks"
            case .live: return "Live"
            case .projects: return "Projects"
            case .usage: return "Usage"
            case .host: return "Host"
            case .vms: return "VMs"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .tasks: return "checklist"
            case .live: return "dot.radiowaves.left.and.right"
            case .projects: return "folder.fill"
            case .usage: return "chart.bar.fill"
            case .host: return "desktopcomputer"
            case .vms: return "server.rack"
            case .settings: return "gearshape.fill"
            }
        }

        init?(name: String) {
            self.init(rawValue: name.lowercased())
        }
    }

    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @EnvironmentObject private var router: MobileRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The custom dock's selection. It includes Usage and VMs, which sit
    /// outside the five-item `TabView` so UIKit does not wrap the sixth item in
    /// “More”. The system tab bar itself stays hidden.
    @State private var selection: Tab = .tasks
    /// The five tabs owned by the system `TabView`.
    @State private var tabSelection: Tab = .tasks

    /// Landscape moves the tab strip to the left edge as a text-only rail so
    /// the short side of the screen is not spent on a bottom bar.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        // The tab strip moves between the bottom edge (portrait) and the
        // leading edge (landscape) while staying the second child of the
        // layout, so the tab content keeps its identity — and with it the
        // navigation stacks and scroll positions — across rotation.
        let layout = isLandscape
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))

        layout {
            if isLandscape {
                MobileTabBar(selection: $selection, axis: .vertical, showsIcons: false)
                    .padding(.vertical, 18)
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
            }

            content

            if !isLandscape {
                MobileTabBar(selection: $selection)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
        }
        .background { MobileTheme.background.ignoresSafeArea() }
        .onChange(of: selection) { _, newValue in
            // Keep the hidden TabView on the last system tab so returning to
            // it preserves its navigation stack and scroll position.
            if newValue != .usage && newValue != .vms {
                tabSelection = newValue
            }
        }
        .task { store.start() }
        .task {
            #if DEBUG
            if let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_TAB"],
               let tab = Tab(name: requested) {
                selection = tab
                return
            }
            #endif
            if !settings.isConfigured { selection = .settings }
        }
        .onOpenURL { url in
            if settings.applyPairingLink(url.absoluteString) {
                store.reconnect()
                selection = .tasks
                return
            }
            if router.handle(url) {
                if let tab = router.requestedTab { selection = tab }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.resume()
            case .background:
                store.pause()
                store.publishWidgetSnapshot(force: true)
            default:
                break
            }
        }
    }

    private var content: some View {
        ZStack {
            TabView(selection: $tabSelection) {
                TasksView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.tasks)

                LiveView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.live)

                ProjectsView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.projects)

                HostView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.host)

                NavigationStack { SettingsView() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.settings)
            }
            .opacity(selection == .usage || selection == .vms ? 0 : 1)
            .allowsHitTesting(selection != .usage && selection != .vms)

            if selection == .usage {
                UsageView()
                    .transition(.opacity)
            }

            if selection == .vms {
                VirtualMachinesView()
                    .transition(.opacity)
            }
        }
    }
}

/// Compact floating tab strip. Mirrors the segmented switcher at the top of the
/// Mac panel, moved to the thumb reach on iPhone. In landscape it becomes a
/// vertical text-only rail pinned to the leading edge.
struct MobileTabBar: View {
    @Binding var selection: RootView.Tab
    var axis: Axis = .horizontal
    var showsIcons = true
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectionNamespace
    /// The selection indicator animates on its own. Applying `withAnimation`
    /// to the tab selection itself also animated the whole destination tab
    /// (charts, materials, live rows) during every switch, which made tab
    /// changes feel slow on device.
    @State private var highlighted: RootView.Tab = .tasks

    private var layout: AnyLayout {
        axis == .vertical
            ? AnyLayout(VStackLayout(spacing: 2))
            : AnyLayout(HStackLayout(spacing: 3))
    }

    var body: some View {
        layout {
            ForEach(RootView.Tab.allCases) { tab in
                Button {
                    selection = tab
                    withAnimation(.easeInOut(duration: 0.18)) {
                        highlighted = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        if showsIcons {
                            Image(systemName: tab.icon)
                                .font(.system(size: 15, weight: .semibold))
                        }
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(maxWidth: axis == .horizontal ? CGFloat.infinity : nil)
                    .padding(.vertical, 7)
                    .padding(.horizontal, axis == .vertical ? 10 : 0)
                    .foregroundStyle(highlighted == tab ? Color.primary : Color.secondary)
                    .background {
                        if highlighted == tab {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(colorScheme == .dark ? Color.primary.opacity(0.11) : .white)
                                .shadow(
                                    color: colorScheme == .dark ? .clear : .black.opacity(0.10),
                                    radius: 3,
                                    y: 1
                                )
                                .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .onAppear { highlighted = selection }
        .onChange(of: selection) { _, newValue in
            // Programmatic changes (pairing link, first-run settings) still
            // move the indicator, but the tab content switches immediately.
            if highlighted != newValue {
                withAnimation(.easeInOut(duration: 0.18)) {
                    highlighted = newValue
                }
            }
        }
        .padding(5)
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12),
            radius: 18,
            y: 8
        )
    }
}
