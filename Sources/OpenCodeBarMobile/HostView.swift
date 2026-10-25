import SwiftUI

/// The System inventory and Remote desktop share one tab so the phone keeps a
/// five-item tab bar. iOS turns a sixth tab into a "More" stack, which would
/// wrap Remote in an extra navigation controller.
enum HostMode: String, CaseIterable, Identifiable {
    case system
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .remote: return "Remote"
        }
    }

    var icon: String {
        switch self {
        case .system: return "cpu"
        case .remote: return "display"
        }
    }
}

struct HostView: View {
    @EnvironmentObject private var router: MobileRouter
    @State private var mode: HostMode = .system

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .system:
                    SystemView()
                case .remote:
                    RemoteDesktopView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Host section", selection: $mode) {
                        ForEach(HostMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
        .onAppear {
            #if DEBUG
            if let requested = ProcessInfo.processInfo.environment["OPENCODEBAR_HOST_MODE"],
               let value = HostMode(rawValue: requested.lowercased()) {
                mode = value
            }
            #endif
            if let requested = router.requestedHostMode {
                mode = requested
                router.requestedHostMode = nil
            }
        }
        .onChange(of: router.requestedHostMode) { _, requested in
            guard let requested else { return }
            mode = requested
            router.requestedHostMode = nil
        }
    }
}
