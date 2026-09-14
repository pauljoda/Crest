import Foundation

extension BrowserExtensionControllerPool {
    func registerWindow(
        id: BrowserWindowID, browser: BrowserStore,
        pageProvider: any BrowserExtensionPageProviding,
        focus: @escaping () -> Void, close: @escaping () -> Void
    ) {
        tabWindowCoordinator.registerWindow(
            id: id, browser: browser, pageProvider: pageProvider, focus: focus, close: close)
    }

    func unregisterWindow(id: BrowserWindowID) {
        tabWindowCoordinator.unregisterWindow(id: id)
    }

    func setHostWindowFocused(_ isFocused: Bool, windowID: BrowserWindowID) {
        tabWindowCoordinator.setHostWindowFocused(isFocused, windowID: windowID)
    }

    func setExtensionTabOwner(_ tabID: TabID, in spaceID: SpaceID, windowID: BrowserWindowID) {
        tabWindowCoordinator.setExtensionTabOwner(tabID, in: spaceID, windowID: windowID)
    }

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
        in spaceID: SpaceID,
        windowID: BrowserWindowID? = nil
    ) {
        tabWindowCoordinator.registerTransientTab(tab, in: spaceID, windowID: windowID)
    }

    func unregisterTransientExtensionTab(
        _ tabID: TabID,
        in spaceID: SpaceID
    ) {
        tabWindowCoordinator.unregisterTransientTab(tabID, in: spaceID)
    }

    func extensionWindow(
        in spaceID: SpaceID,
        windowID: BrowserWindowID? = nil
    ) -> BrowserExtensionWindowAdapter? {
        if let windowID { return tabWindowCoordinator.windowsBySpace[spaceID]?[windowID] }
        return tabWindowCoordinator.window(for: spaceID)
    }

    func sidebarEventMessage(_ event: BrowserExtensionSidebarEvent) -> [String: Any]? {
        tabWindowCoordinator.sidebarEventMessage(event)
    }

    func tabGroupEventMessage(_ event: BrowserExtensionTabGroupEvent) -> [String: Any] {
        tabWindowCoordinator.tabGroupEventMessage(event)
    }

    func debuggerEventMessage(_ event: BrowserExtensionDebuggerEvent) -> [String: Any]? {
        tabWindowCoordinator.debuggerEventMessage(event)
    }

    func externalMessageEventMessage(
        _ delivery: BrowserExtensionExternalMessageDelivery
    ) -> [String: Any]? {
        tabWindowCoordinator.externalMessageEventMessage(delivery)
    }

    func declarativeNetRequestEventMessage(
        _ rulesets: BrowserExtensionEmulatedHeaderRulesets
    ) -> [String: Any] {
        tabWindowCoordinator.declarativeNetRequestEventMessage(rulesets)
    }

    func debuggerIdentity(
        forTarget target: BrowserExtensionDebuggerTarget
    ) -> BrowserExtensionDebuggerIdentity? {
        tabWindowCoordinator.debuggerIdentity(forTarget: target)
    }

    func debuggerIdentity(
        for client: BrowserExtensionServiceClientID
    ) -> BrowserExtensionDebuggerIdentity? {
        tabWindowCoordinator.debuggerIdentity(for: client)
    }

    func extensionTab(
        _ tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserExtensionTabAdapter? {
        tabWindowCoordinator.tab(for: tabID, in: spaceID)
    }
}
