import SwiftUI

@main
struct OpenCodeBarMobileApp: App {
    @StateObject private var settings: HubSettingsStore
    @StateObject private var store: MobileStore
    @StateObject private var appearance: AppearanceStore

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
                .tint(Theme.accent)
                .preferredColorScheme(appearance.appearance.colorScheme)
        }
    }
}

struct RootView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case live
        case projects
        case usage
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .live: return "Live"
            case .projects: return "Projects"
            case .usage: return "Usage"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .projects: return "folder.fill"
            case .usage: return "chart.bar.fill"
            case .settings: return "gearshape.fill"
            }
        }

        init?(name: String) {
            self.init(rawValue: name.lowercased())
        }
    }

    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .live

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selection) {
                LiveView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.live)

                ProjectsView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.projects)

                UsageView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.usage)

                NavigationStack { SettingsView() }
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.settings)
            }

            MobileTabBar(selection: $selection)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 4)
        }
        .background { MobileTheme.background.ignoresSafeArea() }
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
            guard settings.applyPairingLink(url.absoluteString) else { return }
            store.reconnect()
            selection = .live
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                store.resume()
            case .background:
                store.pause()
            default:
                break
            }
        }
    }
}

/// Compact floating tab strip. Mirrors the segmented switcher at the top of the
/// Mac panel, moved to the thumb reach on iPhone.
struct MobileTabBar: View {
    @Binding var selection: RootView.Tab
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var selectionNamespace

    var body: some View {
        HStack(spacing: 3) {
            ForEach(RootView.Tab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
                    .background {
                        if selection == tab {
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
