import SwiftUI
import UIKit

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
        case projects
        case usage
        case host
        case vms
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .tasks: return "Tasks"
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
    @Environment(\.colorScheme) private var colorScheme
    /// The custom dock's selection. It includes Usage and VMs, which sit
    /// outside the four-item `TabView` so UIKit does not wrap them in “More”.
    /// The system tab bar itself stays hidden.
    @State private var selection: Tab = .tasks
    /// The tabs owned by the system `TabView`.
    @State private var tabSelection: Tab = .tasks

    /// Landscape moves the tab strip into the leading safe-area strip as an
    /// icon-only rail. On edge-to-edge phones the sensor housing sits in that
    /// strip, so the icons split into two groups above and below the notch
    /// instead of running beside it.
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        let metrics = windowMetrics
        let rail = landscapeRailMetrics(
            screenHeight: metrics.size.height,
            insets: metrics.insets
        )
        // The tab strip moves between the bottom edge (portrait) and the
        // leading edge (landscape) while staying the second child of the
        // layout, so the tab content keeps its identity — and with it the
        // navigation stacks and scroll positions — across rotation.
        let layout = isLandscape
            ? AnyLayout(HStackLayout(spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))

        layout {
            if isLandscape {
                if rail.gap > 0 {
                    // Keep the leading slot so the tab content stays the
                    // second child and keeps its identity across rotation.
                    Color.clear.frame(width: 0)
                } else {
                    landscapeRail(rail)
                }
            }

            content

            if !isLandscape {
                MobileTabBar(selection: $selection)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
        }
        .overlay {
            if isLandscape, rail.gap > 0 {
                // The rail lives in the leading safe-area strip, in line with
                // the notch. A full-screen geometry reader lets it use that
                // strip without moving the content out of the safe area.
                GeometryReader { _ in
                    landscapeRail(rail)
                        .position(x: rail.centerX, y: rail.centerY)
                }
                .ignoresSafeArea()
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
            if let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_TAB"] {
                // Old screenshot scripts still ask for the Live tab.
                if requested.lowercased() == "live" {
                    selection = .tasks
                    return
                }
                if let tab = Tab(name: requested) {
                    selection = tab
                    return
                }
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

    // MARK: - Landscape rail

    private var windowMetrics: (size: CGSize, insets: EdgeInsets) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let window = scene.windows.first
        else {
            return (.zero, EdgeInsets())
        }
        let insets = window.safeAreaInsets
        return (
            window.bounds.size,
            EdgeInsets(
                top: insets.top,
                leading: insets.left,
                bottom: insets.bottom,
                trailing: insets.right
            )
        )
    }

    private struct LandscapeRail {
        var width: CGFloat = 44
        var itemSize: CGFloat = 42
        var itemWidth: CGFloat = 42
        var iconSize: CGFloat = 19
        var gap: CGFloat = 0
        var centerX: CGFloat = 0
        var centerY: CGFloat = 0
    }

    private func landscapeRailMetrics(
        screenHeight: CGFloat,
        insets: EdgeInsets
    ) -> LandscapeRail {
        // Edge-to-edge phones report a leading safe-area inset in landscape
        // even though the notch itself only covers the middle of that edge.
        guard insets.leading >= 40, screenHeight > 0 else {
            return LandscapeRail()
        }

        let spacing: CGFloat = 2
        let padding: CGFloat = 5
        // The notch is a portrait-width cutout turned on its side. A 12 Pro
        // notch is about 49% of the screen width; the Dynamic Island is
        // narrower. Six points keep the capsule caps off the housing.
        let gap = screenHeight * (insets.leading >= 55 ? 0.32 : 0.49) + 6
        // Landscape splits six icons three above and three below the notch,
        // which keeps the rail symmetric and the icons legible on notched
        // phones.
        let topLimit = insets.top + 16
        let bottomLimit = screenHeight - insets.bottom
        let halfSpace = min(
            screenHeight / 2 - gap / 2 - topLimit,
            bottomLimit - screenHeight / 2 - gap / 2
        )
        let available = halfSpace - 2 * padding - 2 * spacing
        let itemSize = max(14, min(42, floor(available / 3)))
        let iconSize = min(19, itemSize * 0.95)

        // The groups are symmetric, so centring the rail centres the gap on
        // the sensor housing. The capsule is wider than the icons and right
        // aligned with the safe-area edge, so it reads as a rail rather than a
        // floating pill in the margin.
        let centerY = screenHeight / 2
        let itemWidth = itemSize + 10
        let width = itemWidth + 2 * padding
        let centerX = insets.leading - width / 2

        return LandscapeRail(
            width: width,
            itemSize: itemSize,
            itemWidth: itemWidth,
            iconSize: iconSize,
            gap: gap,
            centerX: centerX,
            centerY: centerY
        )
    }

    @ViewBuilder
    private func landscapeRail(_ rail: LandscapeRail) -> some View {
        let tabs = RootView.Tab.allCases
        if rail.gap > 0 {
            VStack(spacing: 0) {
                MobileTabBar(
                    selection: $selection,
                    axis: .vertical,
                    showsTitles: false,
                    tabs: Array(tabs.prefix(3)),
                    verticalItemSize: rail.itemSize,
                    verticalItemWidth: rail.itemWidth,
                    verticalIconSize: rail.iconSize,
                    showsBackground: false
                )
                Color.clear
                    .frame(height: rail.gap)
                    .accessibilityHidden(true)
                MobileTabBar(
                    selection: $selection,
                    axis: .vertical,
                    showsTitles: false,
                    tabs: Array(tabs.dropFirst(3)),
                    verticalItemSize: rail.itemSize,
                    verticalItemWidth: rail.itemWidth,
                    verticalIconSize: rail.iconSize,
                    showsBackground: false
                )
            }
            .frame(width: rail.width)
            .background {
                // One rail behind both groups. The sensor housing cuts the
                // leading edge, so the strip stays connected beside the notch
                // instead of reading as two floating buttons.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.28 : 0.10),
                radius: 14,
                x: 6
            )
        } else {
            MobileTabBar(
                selection: $selection,
                axis: .vertical,
                showsTitles: false,
                tabs: tabs
            )
            .padding(.vertical, 12)
            .padding(.leading, 6)
            .padding(.trailing, 4)
        }
    }

    private var content: some View {
        ZStack {
            TabView(selection: $tabSelection) {
                TasksView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(Tab.tasks)

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
        .overlay(alignment: .top) {
            if let update = store.otaUpdate {
                OtaUpdateBanner(
                    artifact: update,
                    onInstall: { store.openOtaInstallPage(for: update) },
                    onDismiss: { store.dismissOtaUpdate(update) }
                )
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.otaUpdate?.id)
    }
}

/// Compact floating tab strip. Mirrors the segmented switcher at the top of the
/// Mac panel, moved to the thumb reach on iPhone. In landscape it becomes a
/// vertical icon-only rail pinned to the leading edge.
struct MobileTabBar: View {
    @Binding var selection: RootView.Tab
    var axis: Axis = .horizontal
    var showsIcons = true
    var showsTitles = true
    var tabs: [RootView.Tab] = RootView.Tab.allCases
    var verticalItemSize: CGFloat = 42
    var verticalItemWidth: CGFloat?
    var verticalIconSize: CGFloat = 19
    var showsBackground = true
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
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                    withAnimation(.easeInOut(duration: 0.18)) {
                        highlighted = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        if showsIcons {
                            Image(systemName: tab.icon)
                                .font(.system(
                                    size: axis == .vertical ? verticalIconSize : 15,
                                    weight: .semibold
                                ))
                        }
                        if showsTitles {
                            Text(tab.title)
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .frame(maxWidth: axis == .horizontal ? CGFloat.infinity : nil)
                    .frame(
                        width: axis == .vertical
                            ? (verticalItemWidth ?? verticalItemSize)
                            : nil,
                        height: axis == .vertical ? verticalItemSize : nil
                    )
                    .padding(.vertical, axis == .vertical ? 0 : 7)
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
            if showsBackground {
                RoundedRectangle(cornerRadius: axis == .vertical ? 26 : 19, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if showsBackground {
                RoundedRectangle(cornerRadius: axis == .vertical ? 26 : 19, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .shadow(
            color: showsBackground
                ? .black.opacity(colorScheme == .dark ? 0.35 : 0.12)
                : .clear,
            radius: 18,
            x: axis == .vertical ? 8 : 0,
            y: axis == .vertical ? 0 : 8
        )
    }
}
