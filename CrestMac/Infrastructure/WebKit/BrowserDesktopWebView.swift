import AppKit
import WebKit

@MainActor
final class BrowserDesktopWebView: WKWebView {
    /// The page that owns this view. Weak because the page owns it.
    weak var menuHost: (any BrowserDesktopWebViewMenuHost)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// Appends Crest's own items to the menu WebKit just built.
    ///
    /// AppKit calls this with the finished menu, which is the one moment a
    /// link-aware item can be added: WebKit's items stay exactly as WebKit
    /// ordered them, and the destination comes from the `contextmenu` report
    /// the content bridge posted a moment earlier rather than from a second
    /// hit test of Crest's own.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let context = menuHost?.takeMenuContext() else { return }
        if let imageDownloadURL = context.imageDownloadURL,
            let item = BrowserDesktopWebViewMenuPolicy.downloadImageItem(in: menu)
        {
            item.target = self
            item.action = #selector(downloadImage(_:))
            item.representedObject = imageDownloadURL
        }
        guard let destination = context.splitViewLinkDestination else { return }
        if let last = menu.items.last, !last.isSeparatorItem {
            menu.addItem(.separator())
        }
        let item = NSMenuItem(
            title: String(localized: "Open Link in Split View"),
            action: #selector(openLinkInSplitView(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = destination
        menu.addItem(item)
    }

    /// A capture belongs to one menu. Whatever this one did not use is dropped
    /// here, so the next right-click starts from nothing even if its own report
    /// never arrives.
    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        menuHost?.discardSplitViewLinkCapture()
    }

    @objc private func openLinkInSplitView(_ sender: NSMenuItem) {
        guard let destination = sender.representedObject as? URL else { return }
        menuHost?.openLinkInSplitView(destination)
    }

    @objc private func downloadImage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        menuHost?.downloadImage(from: url)
    }
}

enum BrowserDesktopWebViewMenuPolicy {
    static let downloadImageIdentifier = NSUserInterfaceItemIdentifier(
        "WKMenuItemIdentifierDownloadImage"
    )

    static func downloadImageItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.identifier == downloadImageIdentifier }
    }
}
