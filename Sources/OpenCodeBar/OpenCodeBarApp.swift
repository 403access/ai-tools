import SwiftUI

struct OpenCodeBarApp: App {
    @StateObject private var state: AppState

    init() {
        let state = AppState()
        _state = StateObject(wrappedValue: state)
        state.start()
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(state)
        } label: {
            MenuBarLabel(activeCount: state.activeCount)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The always-visible menu bar item: a terminal glyph plus the active session
/// count when sessions are running.
struct MenuBarLabel: View {
    let activeCount: Int

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: activeCount > 0 ? "terminal.fill" : "terminal")
            if activeCount > 0 {
                Text("\(activeCount)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(activeCount > 0 ? "\(activeCount) active OpenCode sessions" : "OpenCode")
    }
}
