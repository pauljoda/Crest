import AppKit

extension NSMenu {
    // MARK: - Variables

    /// WebKit's Download Image item, when the menu has one.
    var webKitDownloadImageItem: NSMenuItem? {
        items.first { $0.identifier == .webKitDownloadImage }
    }

    /// WebKit's item that opens a link in a new page, which Crest opens as a
    /// new tab, when the menu has one.
    var webKitLinkDestinationItem: NSMenuItem? {
        items.first { $0.identifier == .webKitOpenLinkInNewWindow }
    }

    // MARK: - Actions - WebKit items

    /// Drops WebKit's selection search, which would leave Crest's own search.
    func removeWebKitSelectionSearch() {
        if let item = items.first(where: { $0.identifier == .webKitSearchWeb }) {
            removeItem(item)
        }
    }

    /// Names WebKit's open-link item for where Crest actually opens it,
    /// keeping its action and shortcut.
    func relabelWebKitLinkDestination() {
        webKitLinkDestinationItem?.title = String(localized: "Open Link in New Tab")
    }
}
