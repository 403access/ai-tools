import SwiftUI

/// Full-panel deployment page for one physical device: what is installed now,
/// and every install the hub knows about. Opened from Settings → Deployments.
struct DeploymentDeviceDetail: View {
    @EnvironmentObject private var state: AppState
    let device: DeploymentDevice

    /// Read the device back from state so a scan updates the page in place.
    private var liveDevice: DeploymentDevice {
        state.deploymentDevices.first(where: { $0.key == device.key }) ?? device
    }

    private var history: [Deployment] {
        state.deploymentHistory(for: liveDevice)
    }

    private var current: [Deployment] {
        liveDevice.current
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            navigationBar
            summary

            if let error = state.deploymentsError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            } else if let notice = state.deploymentsNotice {
                NoticeRow(icon: "exclamationmark.triangle", message: notice, tint: Theme.warn)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    installedSection
                    historySection
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .task { await state.refreshDeployments() }
        .onExitCommand { state.closeDeploymentDevice() }
    }

    // MARK: - Header

    private var navigationBar: some View {
        HStack(spacing: 8) {
            Button {
                state.closeDeploymentDevice()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Settings")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to settings")

            Spacer(minLength: 8)

            Button {
                Task { await state.scanDeployments() }
            } label: {
                if state.isScanningDeployments {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .help("Scan this device for installed builds")
            .disabled(state.isScanningDeployments)

            if liveDevice.connected {
                HStack(spacing: 5) {
                    PulsingDot(size: 6)
                    Text("Connected")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.running)
                }
            } else {
                Chip(text: liveDevice.stateLabel)
            }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Image(systemName: liveDevice.icon)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(liveDevice.connected || liveDevice.isReachable ? Theme.accent : Color.secondary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(liveDevice.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)

                    Text(subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Label(
                    liveDevice.isReachable ? "Reachable" : liveDevice.stateLabel,
                    systemImage: liveDevice.isReachable ? "wifi" : "wifi.slash"
                )
                if let synced = liveDevice.lastSyncedDate {
                    Label("Updated \(Fmt.relative(from: synced))", systemImage: "clock")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    private var subtitle: String {
        var parts = [liveDevice.model, liveDevice.platform]
        if !liveDevice.key.isEmpty {
            parts.append(String(liveDevice.key.prefix(8)))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - Sections

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Installed now") {
                Text("\(current.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if current.isEmpty {
                EmptyState(
                    icon: "iphone.slash",
                    title: liveDevice.lastSynced == nil
                        ? "Not scanned yet"
                        : "No OpenCodeBar build",
                    subtitle: liveDevice.isReachable
                        ? "Install with `make mobile-device`, then scan to confirm what the device has."
                        : "Scan reads installed apps; wake or unlock the phone and scan again."
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(current) { deployment in
                        DeploymentBuildCard(deployment: deployment)
                    }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("History") {
                Text("\(history.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if history.isEmpty {
                Text("Installs reported by the scripts and scans appear here.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(history) { deployment in
                        DeploymentInstallRow(deployment: deployment)
                    }
                }
                .card(padding: 10)
            }
        }
    }
}
