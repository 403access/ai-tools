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

    // MARK: - Over-the-air

    func applyOta(_ payload: OtaPayload) {
        otaLatest = payload.latest
        otaBuilds = payload.builds
        otaBuild = payload.build
        otaFetchedAt = Date()
        isOtaBuilding = payload.build.isRunning
    }

    func refreshOta(force: Bool = false) async {
        guard let api else { return }
        if !force, let fetched = otaFetchedAt, Date().timeIntervalSince(fetched) < 10 {
            return
        }

        do {
            applyOta(try await api.otaBuilds())
            otaError = nil
            // A build started in another window (or before a relaunch) should
            // keep reporting progress here too.
            if otaBuild?.isRunning == true { await watchOtaBuild(using: api) }
        } catch APIError.request(404, _) {
            otaError = "This hub does not publish over-the-air builds yet. Restart it."
        } catch {
            otaError = message(for: error)
        }
    }

    /// Asks the hub to archive, export, and publish a build, then follows its
    /// output until it finishes. The hub does the work, so this keeps running
    /// while the Settings panel is open.
    func startOtaBuild() async {
        guard let api, !isOtaBuilding else { return }
        otaError = nil
        otaNotice = nil
        isOtaBuilding = true

        do {
            applyOtaBuild(try await api.startOtaBuild())
            await watchOtaBuild(using: api)
        } catch {
            isOtaBuilding = false
            otaError = message(for: error)
        }
    }

    /// The public origin the phone should load the install page from. Mirrors
    /// the pairing QR: tunnel first, then the Mac's LAN address.
    var otaShareOrigin: URL? {
        guard let api else { return nil }
        return pairingHubURL(fallingBackTo: api.baseURL)
    }

    func otaInstallPageURL(for artifact: OtaArtifact) -> URL? {
        otaShareOrigin?.appendingPathComponent("api/deployments/ota/\(artifact.id)")
    }

    /// True when the share URL would fail on the phone: iOS rejects
    /// `itms-services` installs over plain HTTP.
    var otaNeedsHTTPS: Bool {
        otaShareOrigin?.scheme?.lowercased() != "https"
    }

    private func applyOtaBuild(_ status: OtaBuildStatus) {
        otaBuild = status
        isOtaBuilding = status.isRunning
    }

    private func watchOtaBuild(using api: HubAPI) async {
        isOtaBuilding = true
        var status = otaBuild
        while status?.isRunning == true {
            do {
                try await Task.sleep(for: .milliseconds(1_500))
            } catch {
                // The view went away; the hub keeps building and a refresh
                // picks the result up later.
                isOtaBuilding = false
                return
            }

            do {
                status = try await api.otaBuildStatus()
                if let status { applyOtaBuild(status) }
            } catch {
                isOtaBuilding = false
                otaError = message(for: error)
                return
            }
        }

        isOtaBuilding = false
        guard let status else { return }
        switch status.state {
        case "succeeded":
            let label = status.artifact?.buildLabel ?? "a new build"
            otaNotice = "Published \(label)."
            await refreshOta(force: true)
        case "failed":
            otaError = status.error ?? "The build failed. Check the output above."
        default:
            break
        }
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
