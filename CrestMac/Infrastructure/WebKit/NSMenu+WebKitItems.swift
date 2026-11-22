import AppKit

extension NSMenu {
    // MARK: - Variables

    /// WebKit's Download Image item, when the menu has one.
    var webKitDownloadImageItem: NSMenuItem? {
        items.first { $0.identifier == .webKitDownloadImage }
    }

    /// WebKit's Paste item, when the menu has one.
    var webKitPasteItem: NSMenuItem? {
        items.first { $0.identifier == .webKitPaste }
    }

    // MARK: - Actions - WebKit items

    /// Drops WebKit's selection search, which would leave Crest's own search.
    func removeWebKitSelectionSearch() {
        if let item = items.first(where: { $0.identifier == .webKitSearchWeb }) {
            removeItem(item)
        }
    }

    /// WebKit's open-link-in-a-new-window item, named for where Crest opens
    /// it, a new tab of the page's Space, keeping its action and shortcut.
    func webKitOpenLinkInNewTabItem() -> NSMenuItem? {
        guard let item = items.first(where: { $0.identifier == .webKitOpenLinkInNewWindow }) else { return nil }
        item.title = String(localized: "Open Link in New Tab")
        return item
    }
}
