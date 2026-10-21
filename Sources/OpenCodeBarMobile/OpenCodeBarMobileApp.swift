import SwiftUI

@main
struct OpenCodeBarMobileApp: App {
    @StateObject private var settings: HubSettingsStore
    @StateObject private var store: MobileStore

    init() {
        let settings = HubSettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: MobileStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    enum Tab: Hashable {
        case live
        case projects
        case usage
        case settings

        init?(name: String) {
            switch name.lowercased() {
            case "live": self = .live
            case "projects": self = .projects
            case "usage": self = .usage
            case "settings": self = .settings
            default: return nil
            }
        }
    }

    @EnvironmentObject private var settings: HubSettingsStore
    @EnvironmentObject private var store: MobileStore
    @State private var selection: Tab = .live

    var body: some View {
        TabView(selection: $selection) {
            LiveView()
                .tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }
                .tag(Tab.live)

            ProjectsView()
                .tabItem { Label("Projects", systemImage: "folder") }
                .tag(Tab.projects)

            UsageView()
                .tabItem { Label("Usage", systemImage: "chart.bar.xaxis") }
                .tag(Tab.usage)

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
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
            guard settings.applyPairingLink(url.absoluteString) else { return }
            store.reconnect()
            selection = .live
        }
    }
}
