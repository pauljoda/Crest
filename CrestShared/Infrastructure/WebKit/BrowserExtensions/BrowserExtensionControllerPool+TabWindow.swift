import Foundation

extension BrowserExtensionControllerPool {
    func connect<PageProvider: BrowserExtensionPageProviding>(
        browser: BrowserStore,
        pageProvider: PageProvider
    ) {
        tabWindowCoordinator.connect(
            browser: browser,
            pageProvider: pageProvider,
            openCommandSettings: { [weak self] route, spaceID in
                self?.handleCommandSettingsRoute(route, in: spaceID) == true
            }
        )
    }

    func reconcileExtensionState(in session: BrowserSession) {
        tabWindowCoordinator.reconcile(session: session)
    }

    func setHostWindowFocused(_ isFocused: Bool) {
        tabWindowCoordinator.setHostWindowFocused(isFocused)
    }

    func registerTransientExtensionTab(
        _ tab: BrowserExtensionTransientTab,
        in spaceID: SpaceID
    ) {
        tabWindowCoordinator.registerTransientTab(tab, in: spaceID)
    }

    func unregisterTransientExtensionTab(
        _ tabID: TabID,
        in spaceID: SpaceID
    ) {
        tabWindowCoordinator.unregisterTransientTab(tabID, in: spaceID)
    }

    func extensionWindow(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowAdapter? {
        tabWindowCoordinator.window(for: spaceID)
    }

    func sidebarEventMessage(_ event: BrowserExtensionSidebarEvent) -> [String: Any]? {
        tabWindowCoordinator.sidebarEventMessage(event)
    }

    func tabGroupEventMessage(_ event: BrowserExtensionTabGroupEvent) -> [String: Any] {
        tabWindowCoordinator.tabGroupEventMessage(event)
    }

    func extensionTab(
        _ tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabAdapter? {
        tabWindowCoordinator.tab(for: tabID, in: spaceID)
    }
}
