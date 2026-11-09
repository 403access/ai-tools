import SwiftUI

struct PanelView: View {
    @EnvironmentObject var state: AppState

    /// Fixed panel height. The popover sizes to its content, so keeping the
    /// height the same across tabs and the session detail view avoids the
    /// window resizing — and leaving a gap — when navigating.
    static let panelWidth: CGFloat = 400
    static let panelHeight: CGFloat = 626

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider().opacity(0.5)

            if let path = state.fileBrowserPath {
                SystemFileBrowser(initialPath: path)
                    .id(path)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let device = state.selectedDeploymentDevice {
                DeploymentDeviceDetail(device: device)
                    .id(device.key)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if let device = state.selectedDevice {
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
                ProjectDetailView(project: project, initialMode: state.projectMode)
                    .frame(maxHeight: .infinity)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                TabBar(selection: $state.tab, reviewCount: state.reviewTaskCount)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                Group {
                    if state.tab == .tasks {
                        // The task tab owns its scrolling so the wide board can
                        // pin its headers and stretch columns to fill the area.
                        TasksTab()
                            .padding(12)
                            .frame(maxHeight: .infinity)
                    } else if state.tab.scrollsItself {
                        UsageTab()
                            .padding(12)
                            .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                switch state.tab {
                                case .tasks:
                                    TasksTab()
                                case .usage:
                                    // Handled above; it owns its scroll view.
                                    EmptyView()
                                case .projects:
                                    ProjectsTab()
                                case .system:
                                    SystemTab()
                                case .vms:
                                    VirtualMachinesTab()
                                case .settings:
                                    SettingsTab()
                                }
                            }
                            .padding(12)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Divider().opacity(0.5)
            FooterView()
        }
        .frame(width: Self.panelWidth)
        .frame(height: Self.panelHeight)
        .animation(.easeInOut(duration: 0.18), value: state.selectedSession?.id)
        .animation(.easeInOut(duration: 0.18), value: state.selectedProject?.id)
        .animation(.easeInOut(duration: 0.18), value: state.selectedDevice?.id)
        .animation(.easeInOut(duration: 0.18), value: state.fileBrowserPath)
        .commandBarHost()
    }
}

struct TabBar: View {
    @Binding var selection: AppState.Tab
    var reviewCount = 0

    var body: some View {
        SmartTabBar(
            tabs: AppState.Tab.allCases.map { tab in
                SmartTab(
                    value: tab,
                    title: tab.rawValue,
                    icon: tab.icon,
                    badge: tab == .tasks && reviewCount > 0 ? "\(reviewCount)" : nil,
                    help: "Show \(tab.rawValue)"
                )
            },
            selection: $selection,
            accessibilityLabel: "Panel sections"
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
