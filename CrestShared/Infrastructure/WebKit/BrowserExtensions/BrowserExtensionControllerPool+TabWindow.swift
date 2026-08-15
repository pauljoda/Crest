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

    func extensionWindow(
        in spaceID: SpaceID
    ) -> BrowserExtensionWindowAdapter? {
        tabWindowCoordinator.window(for: spaceID)
    }

    func extensionTab(
        _ tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabAdapter? {
        tabWindowCoordinator.tab(for: tabID, in: spaceID)
    }
}
