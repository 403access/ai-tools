import SwiftUI

/// Settings → Deployments: every paired iPhone/iPad, the builds installed on it
/// right now, and the install history reported by the scripts and scans.
struct SettingsDeploymentsSection: View {
    @EnvironmentObject private var state: AppState
    @State private var showAllHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Deployments") {
                HStack(spacing: 6) {
                    if state.isScanningDeployments {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    } else if let synced = state.deploymentsSyncedAt {
                        Text(Fmt.relative(from: synced))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .help("Last install report or device scan")
                    }
                    Button {
                        Task { await state.scanDeployments() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isScanningDeployments)
                    .help("Read the apps installed on paired iPhones and iPads")
                    .accessibilityLabel("Scan devices for installed builds")
                }
            }

            if let error = state.deploymentsError {
                NoticeRow(icon: "exclamationmark.triangle.fill", message: error, tint: Theme.warn)
            } else if let notice = state.deploymentsNotice {
                NoticeRow(icon: "exclamationmark.triangle", message: notice, tint: Theme.warn)
            }

            if state.deploymentDevices.isEmpty {
                EmptyState(
                    icon: "shippingbox",
                    title: "No deployments yet",
                    subtitle: "Connect and pair an iPhone or iPad, then install with `make mobile-device`. The scan reads what is installed now."
                )
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(state.deploymentDevices) { device in
                        Button {
                            state.open(device)
                        } label: {
                            DeploymentDeviceRow(device: device)
                        }
                        .buttonStyle(.plain)
                        .help("Show the deployment history for \(device.name)")
                        .accessibilityHint("Opens installed builds and install history")
                    }
                }
            }

            if !state.deploymentHistory.isEmpty {
                recentInstalls
            }
        }
        .task { await state.refreshDeployments() }
    }

    private var recentInstalls: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Recent installs") {
                Text("\(state.deploymentHistory.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            VStack(alignment: .leading, spacing: 9) {
                let limit = showAllHistory ? state.deploymentHistory.count : 6
                ForEach(Array(state.deploymentHistory.prefix(limit))) { deployment in
                    DeploymentInstallRow(deployment: deployment, showsDevice: true)
                }

                if state.deploymentHistory.count > 6 {
                    Button {
                        showAllHistory.toggle()
                    } label: {
                        Text(showAllHistory ? "Show less" : "Show all \(state.deploymentHistory.count)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }
            }
            .card(padding: 10)
        }
    }
}
