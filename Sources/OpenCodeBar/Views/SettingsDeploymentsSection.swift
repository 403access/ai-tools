import SwiftUI

/// Settings → Deployments: every paired iPhone/iPad, the builds installed on it
/// right now, and the install history reported by the scripts and scans.
struct SettingsDeploymentsSection: View {
    @EnvironmentObject private var state: AppState
    @State private var showAllHistory = false

    @State private var installDeviceKey = ""
    @State private var installStatus: InstallStatus = .all
    @State private var installQuery = ""

    private enum InstallStatus: String, CaseIterable, Identifiable {
        case all = "All"
        case installed = "Installed"
        case replaced = "Replaced"
        case uninstalled = "Uninstalled"

        var id: String { rawValue }

        func matches(_ deployment: Deployment) -> Bool {
            switch self {
            case .all: return true
            case .installed: return deployment.isCurrent
            case .replaced: return deployment.endReason == "replaced"
            case .uninstalled: return deployment.endReason == "uninstalled"
            }
        }
    }

    private struct InstallDeviceOption: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

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

            SettingsOtaCard()

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
                Text(installCountLabel)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            installFilters

            if filteredHistory.isEmpty {
                NoticeRow(
                    icon: "line.3.horizontal.decrease.circle",
                    message: "No installs match these filters.",
                    tint: .secondary
                )
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    let limit = showAllHistory ? filteredHistory.count : 6
                    ForEach(Array(filteredHistory.prefix(limit))) { deployment in
                        DeploymentInstallRow(deployment: deployment, showsDevice: true)
                    }

                    if filteredHistory.count > 6 {
                        Button {
                            showAllHistory.toggle()
                        } label: {
                            Text(showAllHistory ? "Show less" : "Show all \(filteredHistory.count)")
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

    private var installFilters: some View {
        HStack(spacing: 8) {
            Picker("Device", selection: $installDeviceKey) {
                Text("All devices").tag("")
                ForEach(installDeviceOptions) { option in
                    Text(option.name).tag(option.key)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 130)
            .help("Filter installs by device")

            Picker("Status", selection: $installStatus) {
                ForEach(InstallStatus.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 100)
            .help("Filter installs by status")

            TextField("Filter installs", text: $installQuery)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

            if hasActiveInstallFilters {
                Button {
                    clearInstallFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear install filters")
                .accessibilityLabel("Clear install filters")
            }
        }
    }

    private var installDeviceOptions: [InstallDeviceOption] {
        var seen = Set<String>()
        return state.deploymentHistory.compactMap { deployment in
            guard seen.insert(deployment.deviceKey).inserted else { return nil }
            let name = deployment.deviceName.isEmpty ? deployment.deviceKey : deployment.deviceName
            return InstallDeviceOption(key: deployment.deviceKey, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredHistory: [Deployment] {
        let needle = installQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return state.deploymentHistory.filter { deployment in
            if !installDeviceKey.isEmpty, deployment.deviceKey != installDeviceKey {
                return false
            }
            guard installStatus.matches(deployment) else { return false }
            guard !needle.isEmpty else { return true }

            let searchable = [
                deployment.deviceName,
                deployment.deviceModel,
                deployment.displayName,
                deployment.buildLabel,
                deployment.shortCommit,
                deployment.branch,
                deployment.bundleId,
                deployment.variant,
            ]
            return searchable.contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    private var hasActiveInstallFilters: Bool {
        !installDeviceKey.isEmpty
            || installStatus != .all
            || !installQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var installCountLabel: String {
        if hasActiveInstallFilters {
            return "\(filteredHistory.count)/\(state.deploymentHistory.count)"
        }
        return "\(state.deploymentHistory.count)"
    }

    private func clearInstallFilters() {
        withAnimation(.easeOut(duration: 0.14)) {
            installDeviceKey = ""
            installStatus = .all
            installQuery = ""
        }
    }
}
