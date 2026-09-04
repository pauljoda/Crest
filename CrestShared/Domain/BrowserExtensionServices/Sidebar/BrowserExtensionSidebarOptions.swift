import Foundation

enum BrowserExtensionSidebarFlavor: String, Equatable, Sendable {
    case sidePanel
    case sidebarAction
}

enum BrowserExtensionSidebarIcon: Equatable, Sendable {
    case packagePath(String)
}

enum BrowserExtensionSidebarScope: Hashable, Sendable {
    case `default`
    case window
    case tab(TabID)
}

/// One override layer. A missing field inherits; an empty path disables the
/// document. API adapters distinguish a missing field from a requested reset.
struct BrowserExtensionSidebarOptions: Equatable, Sendable {
    var path: String?
    var isEnabled: Bool?
    var title: String?
    var icon: BrowserExtensionSidebarIcon?

    mutating func merge(_ update: Self) {
        if let path = update.path { self.path = path }
        if let isEnabled = update.isEnabled { self.isEnabled = isEnabled }
        if let title = update.title { self.title = title }
        if let icon = update.icon { self.icon = icon }
    }
}

struct BrowserExtensionSidebarResolvedOptions: Equatable, Sendable {
    let path: String
    let isEnabled: Bool
    let title: String
    let icon: BrowserExtensionSidebarIcon?
    let scope: BrowserExtensionSidebarScope

    var presentsPanel: Bool { isEnabled && !path.isEmpty }
}
