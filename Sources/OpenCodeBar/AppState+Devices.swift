import Foundation

extension AppState {
    // MARK: - Device detail

    /// Opens the full detail page for a device that has connected to the hub.
    func open(_ device: ConnectedDevice) {
        selectedDevice = device
    }

    func closeDevice() {
        selectedDevice = nil
    }
}
