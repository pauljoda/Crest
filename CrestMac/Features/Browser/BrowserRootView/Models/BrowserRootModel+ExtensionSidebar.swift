extension BrowserRootModel {
    func configureExtensionSidebar(_ store: BrowserExtensionSidebarStore?) {
        guard extensionSidebar == nil, let store else { return }
        extensionSidebar = BrowserExtensionSidebarHost(
            store: store, windowID: extensionSidebarWindowID, browser: browser, pages: pages,
            spaceAccess: spaceAccess, windowState: windowState
        )
        extensionSidebar?.reconcile()
    }
}
