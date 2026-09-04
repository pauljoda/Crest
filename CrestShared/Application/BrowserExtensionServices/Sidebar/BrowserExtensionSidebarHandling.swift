import Foundation

@MainActor
protocol BrowserExtensionSidebarHandling: AnyObject {
    func register(
        client: BrowserExtensionServiceClientID, spaceID: SpaceID,
        defaults: BrowserExtensionSidebarDefaults, displayName: String, baseURL: URL
    )
    func unregister(client: BrowserExtensionServiceClientID)
    func requestOpenAtInstall(for client: BrowserExtensionServiceClientID, didOpen: @escaping () -> Void)
    func setOptions(
        _ options: BrowserExtensionSidebarOptions, scope: BrowserExtensionSidebarScope,
        from client: BrowserExtensionServiceClientID
    ) throws
    func setChromeOptions(
        _ options: BrowserExtensionSidebarOptions, tab: TabID?, from client: BrowserExtensionServiceClientID) throws
    func clearTitle(scope: BrowserExtensionSidebarScope, from client: BrowserExtensionServiceClientID) throws
    func clearIcon(scope: BrowserExtensionSidebarScope, from client: BrowserExtensionServiceClientID) throws
    func layer(_ scope: BrowserExtensionSidebarScope, for client: BrowserExtensionServiceClientID) throws
        -> BrowserExtensionSidebarOptions
    func resolvedOptions(for tab: TabID?, client: BrowserExtensionServiceClientID) throws
        -> BrowserExtensionSidebarResolvedOptions
    func resolvedOptions(at scope: BrowserExtensionSidebarScope, client: BrowserExtensionServiceClientID) throws
        -> BrowserExtensionSidebarResolvedOptions
    func hostWindow(for spaceID: SpaceID) -> BrowserWindowID?
    func flavor(for client: BrowserExtensionServiceClientID) -> BrowserExtensionSidebarFlavor?
    func setBehavior(_ behavior: BrowserExtensionSidebarBehavior, from client: BrowserExtensionServiceClientID) throws
    func behavior(for client: BrowserExtensionServiceClientID) throws -> BrowserExtensionSidebarBehavior
    func open(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws
    func close(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws
    func closeChromePanel(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws
    func toggle(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID, tab: TabID?) throws
    func isOpen(for client: BrowserExtensionServiceClientID, in window: BrowserWindowID) -> Bool
    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionSidebarEvent>
    func repair(using session: BrowserSession)
}

@MainActor
protocol BrowserExtensionSidebarBehaviorPersisting {
    func load(for client: BrowserExtensionServiceClientID) -> BrowserExtensionSidebarBehavior
    func save(_ behavior: BrowserExtensionSidebarBehavior, for client: BrowserExtensionServiceClientID)
}
