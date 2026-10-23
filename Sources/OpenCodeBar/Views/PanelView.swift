import SwiftUI

struct PanelView: View {
    @EnvironmentObject var state: AppState

    /// Fixed panel height. The menu bar popover sizes to its content, so keeping
    /// the height the same across tabs and the session detail view avoids the
    /// window resizing — and leaving a gap — when navigating.
    private static let contentHeight: CGFloat = 626

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider().opacity(0.5)

            if let device = state.selectedDevice {
                DeviceDetailView(device: device)
                    .id(device.id)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let session = state.selectedSession {
                SessionDetailView(session: session, initialMode: state.detailMode)
                    .id(session.id)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let project = state.selectedProject {
                ProjectDetailView(project: project)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                TabBar(selection: $state.tab)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch state.tab {
                        case .live:
                            LiveTab()
                        case .usage:
                            UsageTab()
                        case .projects:
                            ProjectsTab()
                        case .settings:
                            SettingsTab()
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Divider().opacity(0.5)
            FooterView()
        }
        .frame(width: 400)
        .frame(height: Self.contentHeight)
        .animation(.easeInOut(duration: 0.18), value: state.selectedSession?.id)
        .animation(.easeInOut(duration: 0.18), value: state.selectedProject?.id)
        .animation(.easeInOut(duration: 0.18), value: state.selectedDevice?.id)
    }
}

struct TabBar: View {
    @Binding var selection: AppState.Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppState.Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon).font(.system(size: 11, weight: .semibold))
                        Text(tab.rawValue).font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(selection == tab ? Color.primary.opacity(0.12) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? Color.primary : Color.secondary)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct FooterView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.activeCount > 0 ? Theme.running : Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
            Text("\(state.activeCount) active")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer()
            if let updated = state.lastUpdated {
                Text("Updated \(Fmt.relative(from: updated))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }
}
