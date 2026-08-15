import AppKit
import WebKit

@MainActor
struct BrowserExtensionToolbarMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let isEnabled: Bool
    let isSeparator: Bool
    let children: [BrowserExtensionToolbarMenuItem]
    let item: NSMenuItem

    init(item: NSMenuItem) {
        title = item.title
        isEnabled = item.isEnabled
        isSeparator = item.isSeparatorItem
        children = item.submenu?.items.map(Self.init(item:)) ?? []
        self.item = item
    }
}
