import Foundation

extension AppState {
    // MARK: - Device detail

    /// Opens the full detail page for a device that has connected to the hub.
    func open(_ device: ConnectedDevice) {
        sessionStack.removeAll()
        selectedSession = nil
        selectedProject = nil
        fileBrowserPath = nil
        selectedDevice = device
    }

    func closeDevice() {
        selectedDevice = nil
    }
}
