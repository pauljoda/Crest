import AppKit

extension BrowserCommandActions {
    // MARK: - Variables

    /// Whether the Space of the page in front, unlocked, has an extension
    /// whose popup Open Next Extension can open: a Quick Window's own Space,
    /// or the one the browser window shows.
    var canOpenNextExtension: Bool {
        guard let windows, let space = shownPageSpace, !spaceAccess.isLocked(space) else { return false }
        return windows.engineHost.opensExtensions(in: space, page: commandPage)
    }

    // MARK: - Actions - Extensions

    /// Opens the next extension's popup over the page in front, or over the
    /// window when it shows no page, or closes the popup after the last.
    func openNextExtension() {
        guard let windows, let space = shownPageSpace, !spaceAccess.isLocked(space) else { return }
        windows.engineHost.openNextExtension(
            in: space, page: commandPage, window: windows.window(for: targetWindowID))
    }
}
