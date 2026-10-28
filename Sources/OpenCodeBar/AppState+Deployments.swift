import Foundation

/// iPhone/iPad deployments: which build is installed now, and the install
/// history the scripts and device scans recorded.
extension AppState {
    /// Replaces the cached snapshot after a fetch or scan.
    func applyDeployments(_ payload: DeploymentsPayload) {
        deploymentDevices = payload.devices
        deploymentHistory = payload.deployments
        deploymentsSyncedAt = payload.syncedAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        deploymentsFetchedAt = Date()
        // Keep an open detail page live when its device was rescanned.
        if let selected = selectedDeploymentDevice,
           let refreshed = payload.devices.first(where: { $0.key == selected.key }) {
            selectedDeploymentDevice = refreshed
        }
    }

    func refreshDeployments(force: Bool = false) async {
        guard let api else { return }
        if isRefreshingDeployments || isScanningDeployments { return }
        if !force, let fetched = deploymentsFetchedAt,
           Date().timeIntervalSince(fetched) < 10 {
            return
        }

        isRefreshingDeployments = true
        defer { isRefreshingDeployments = false }

        do {
            applyDeployments(try await api.deployments())
            deploymentsError = nil
        } catch APIError.request(404, _) {
            deploymentsError = "This hub does not list deployments yet. Restart it."
        } catch {
            deploymentsError = message(for: error)
        }
    }

    /// Asks the hub to read every paired device with devicectl. Slower than a
    /// plain refresh because it talks to the phones.
    func scanDeployments() async {
        guard let api else { return }
        guard !isScanningDeployments else { return }
        isScanningDeployments = true
        deploymentsNotice = nil
        defer { isScanningDeployments = false }

        do {
            let payload = try await api.scanDeployments()
            applyDeployments(payload)
            deploymentsError = nil
            if let errors = payload.errors, !errors.isEmpty {
                deploymentsNotice = errors.prefix(2).joined(separator: " ")
            }
        } catch {
            deploymentsError = message(for: error)
        }
    }

    // MARK: - Navigation

    /// Opens the deployment history for a physical device.
    func open(_ device: DeploymentDevice) {
        sessionStack.removeAll()
        selectedSession = nil
        selectedProject = nil
        selectedDevice = nil
        fileBrowserPath = nil
        selectedDeploymentDevice = device
    }

    func closeDeploymentDevice() {
        selectedDeploymentDevice = nil
    }

    // MARK: - Helpers

    /// Every history row for one device, newest first (the hub already sorts).
    func deploymentHistory(for device: DeploymentDevice) -> [Deployment] {
        deploymentHistory.filter { $0.deviceKey == device.key }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
