import Foundation

@MainActor
final class InMemoryBrowserExtensionSidebarBehaviorStore: BrowserExtensionSidebarBehaviorPersisting {
    private var values: [BrowserExtensionServiceClientID: BrowserExtensionSidebarBehavior] = [:]

    func load(for client: BrowserExtensionServiceClientID) -> BrowserExtensionSidebarBehavior {
        values[client] ?? .init()
    }

    func save(_ behavior: BrowserExtensionSidebarBehavior, for client: BrowserExtensionServiceClientID) {
        values[client] = behavior
    }
}
