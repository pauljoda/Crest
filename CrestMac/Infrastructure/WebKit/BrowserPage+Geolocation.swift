extension BrowserPage {
    /// Re-reads the stored main-frame decision after the Site Settings popover
    /// changes it.
    func synchronizeGeolocationPermission() {
        geolocationCoordinator?.synchronizeMainFramePermission()
    }
}
