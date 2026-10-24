import Foundation

extension AppState {
    /// Opens the host file browser over the panel. Any session/project/device
    /// detail page is dismissed first so Back returns to the tab that opened it.
    func openFileBrowser(at path: String) {
        selectedSession = nil
        selectedProject = nil
        selectedDevice = nil
        fileBrowserPath = path
    }

    func closeFileBrowser() {
        fileBrowserPath = nil
    }
}
