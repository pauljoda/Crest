extension BrowserPage {
    /// Re-reads the stored main-frame decision after the Site Settings popover
    /// changes it. Only macOS can edit a live page's permission while that page
    /// stays on screen, so this has no mobile counterpart.
    func synchronizeGeolocationPermission() {
        geolocationCoordinator?.synchronizeMainFramePermission()
    }
}
