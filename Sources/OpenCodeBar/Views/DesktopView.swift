import AppKit
import SwiftUI

/// Full-window layout used when OpenCodeBar runs as a desktop app.
///
/// The menu bar panel keeps its compact single-column layout. This view reuses
/// the same tab and detail views, but gives them a persistent sidebar and, when
/// the window is wide enough, a list beside the detail page — so selecting a
/// project or session does not make the list disappear.
struct DesktopView: View {
    @EnvironmentObject private var state: AppState

    /// Widths are measured for the content area only (the sidebar is excluded).
    private enum Split {
        static let twoColumnMin: CGFloat = 700
        static let threeColumnMin: CGFloat = 1120
        static let rootMin: CGFloat = 340
        static let rootMax: CGFloat = 400
        static let middleMin: CGFloat = 340
        static let middleMax: CGFloat = 400
    }

    var body: some View {
        HStack(spacing: 0) {
            DesktopSidebar()
                .frame(width: 220)

            Divider()

            GeometryReader { proxy in
                content(width: proxy.size.width)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .animation(.easeInOut(duration: 0.18), value: state.selectedSession?.id)
        .animation(.easeInOut(duration: 0.18), value: state.selectedProject?.id)
        .animation(.easeInOut(duration: 0.18), value: state.selectedDevice?.id)
        .animation(.easeInOut(duration: 0.18), value: state.fileBrowserPath)
    }

    // MARK: - Layout

    @ViewBuilder
    private func content(width: CGFloat) -> some View {
        if !hasDetail {
            rootList(compact: false)
        } else if width >= Split.twoColumnMin {
            HStack(spacing: 0) {
                rootColumn
                    .frame(width: rootWidth(for: width))

                Divider()

                if hasIntermediate, width >= Split.threeColumnMin {
                    intermediatePane
                        .frame(width: middleWidth(for: width))

                    Divider()
                }

                finalPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            finalPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rootWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.38, Split.rootMin), Split.rootMax)
    }

    private func middleWidth(for width: CGFloat) -> CGFloat {
        min(max(width * 0.30, Split.middleMin), Split.middleMax)
    }

    private var hasDetail: Bool {
        state.fileBrowserPath != nil
            || state.selectedDevice != nil
            || state.selectedSession != nil
            || state.selectedProject != nil
    }

    /// A session opened from a project detail keeps the project selected, so
    /// wide windows can show Projects → Project → Session as three columns.
    private var hasIntermediate: Bool {
        state.fileBrowserPath == nil
            && state.selectedDevice == nil
            && state.selectedProject != nil
            && state.selectedSession != nil
    }

    // MARK: - Columns

    /// The root list of the active tab, with a header when it is a column.
    private var rootColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: state.tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(state.tab.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if state.tab == .tasks, state.reviewTaskCount > 0 {
                    Text("\(state.reviewTaskCount) to review")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.warn)
                } else if state.tab == .live, state.activeCount > 0 {
                    Text("\(state.activeCount) active")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.running)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            rootList(compact: true)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func rootList(compact: Bool) -> some View {
        Group {
            if state.tab.scrollsItself {
                UsageTab()
                    .frame(maxWidth: compact ? .infinity : 1040, alignment: .leading)
                    .padding(compact ? 12 : 20)
                    .frame(maxWidth: .infinity, alignment: .top)
            } else {
                ScrollView {
                    activeTab
                        .frame(maxWidth: compact ? .infinity : 1040, alignment: .leading)
                        .padding(compact ? 12 : 20)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
        }
    }

    @ViewBuilder
    private var activeTab: some View {
        switch state.tab {
        case .tasks:
            TasksTab()
        case .live:
            LiveTab()
        case .usage:
            UsageTab()
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

    @ViewBuilder
    private var intermediatePane: some View {
        if let project = state.selectedProject {
            ProjectDetailView(
                project: project,
                initialMode: state.projectMode,
                showsBackButton: false
            )
            .id(project.id)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var finalPane: some View {
        if let path = state.fileBrowserPath {
            SystemFileBrowser(initialPath: path)
                .id(path)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let device = state.selectedDevice {
            DeviceDetailView(device: device)
                .id(device.id)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let session = state.selectedSession {
            SessionDetailView(session: session, initialMode: state.detailMode)
                .id(session.id)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        } else if let project = state.selectedProject {
            ProjectDetailView(project: project, initialMode: state.projectMode)
                .id(project.id)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}

/// Persistent navigation rail shown in the desktop window.
private struct DesktopSidebar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            navigation
            Spacer(minLength: 12)
            footer
        }
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            logo

            VStack(alignment: .leading, spacing: 1) {
                Text("OpenCode")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(state.connection.label)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            Button {
                Task { await state.refreshAll() }
            } label: {
                if state.isRefreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.65)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(AppState.Tab.allCases) { tab in
                Button {
                    show(tab)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 16)
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 4)
                        if tab == .tasks, state.reviewTaskCount > 0 {
                            Text("\(state.reviewTaskCount)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.warn)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.warn.opacity(0.14)))
                        } else if tab == .live, state.activeCount > 0 {
                            Text("\(state.activeCount)")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Theme.running)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.running.opacity(0.14)))
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .foregroundStyle(selected(tab) ? Color.primary : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(selected(tab) ? Color.primary.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(state.activeCount > 0 ? Theme.running : Color.secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text("\(state.activeCount) active")
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Quit OpenCodeBar")
            }
            if let updated = state.lastUpdated {
                Text("Updated \(Fmt.relative(from: updated))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The active tab stays highlighted while a session, project, device, or
    /// folder detail page is open; Back returns to its list.
    private func selected(_ tab: AppState.Tab) -> Bool {
        state.tab == tab
    }

    /// Choosing a tab leaves any open detail page, mirroring the Back button in
    /// the menu bar panel.
    private func show(_ tab: AppState.Tab) {
        state.selectedSession = nil
        state.selectedProject = nil
        state.selectedDevice = nil
        state.fileBrowserPath = nil
        state.sessionStack.removeAll()
        state.tab = tab
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Theme.accent, Theme.accent.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black.opacity(0.75))
        }
        .frame(width: 28, height: 28)
    }

    private var statusColor: Color {
        switch state.connection {
        case .connected: return Theme.accent
        case .connecting: return Theme.warn
        case .offline: return Theme.danger
        }
    }
}
