import Foundation

@MainActor
final class UserDefaultsBrowserExtensionSidebarBehaviorStore: BrowserExtensionSidebarBehaviorPersisting {
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func load(for client: BrowserExtensionServiceClientID) -> BrowserExtensionSidebarBehavior {
        .init(openPanelOnActionClick: defaults.bool(forKey: key(for: client)))
    }

    func save(_ behavior: BrowserExtensionSidebarBehavior, for client: BrowserExtensionServiceClientID) {
        defaults.set(behavior.openPanelOnActionClick, forKey: key(for: client))
    }

    private func key(for client: BrowserExtensionServiceClientID) -> String {
        "extension.sidebar.action-behavior.\(client.rawValue)"
    }
}
