import AppKit
import WebKit

@MainActor
final class BrowserDesktopWebView: WKWebView {
    /// The page that owns this view. Weak because the page owns it.
    weak var menuHost: (any BrowserDesktopWebViewMenuHost)?
    /// The page-owned record of this view's public AppKit editing responder.
    weak var focusRestoration: BrowserWebFocusRestorationController?
    weak var linkHover: BrowserLinkHoverController?
    weak var linkDrag: BrowserLinkDragController?

    override func mouseDown(with event: NSEvent) {
        linkDrag?.mouseDown(event)
        super.mouseDown(with: event)
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if superview !== newSuperview {
            linkHover?.detach()
            linkDrag?.detach()
        }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            linkHover?.invalidate()
            linkDrag?.detach()
        }
    }

    override func becomeFirstResponder() -> Bool {
        guard focusRestoration?.allowsNativeFocusAcquisition != false else {
            return false
        }
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            focusRestoration?.remember(self)
        }
        return becameFirstResponder
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// Adds Crest's actions ahead of WebKit's native and extension items.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if menuHost?.opensLinksInCurrentSpace == true {
            BrowserDesktopWebViewMenuPolicy.relabelLinkDestination(in: menu)
        }
        BrowserDesktopWebViewMenuPolicy.removeDefaultSelectionSearch(in: menu)
        guard let context = menuHost?.takeMenuContext() else { return }
        let actions = menuHost?.contextMenuActions(
            linkURL: context.linkURL, selectionText: context.selectionText) ?? []
        addCrestActions(actions, to: menu)
        if let imageDownloadURL = context.imageDownloadURL,
            let item = BrowserDesktopWebViewMenuPolicy.downloadImageItem(in: menu)
        {
            item.target = self
            item.action = #selector(downloadImage(_:))
            item.representedObject = imageDownloadURL
        }
    }

    /// A capture belongs to one menu. Whatever this one did not use is dropped
    /// here, so the next right-click starts from nothing even if its own report
    /// never arrives.
    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        menuHost?.discardSplitViewLinkCapture()
    }

    @objc private func performCrestMenuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CrestMenuAction,
            window?.windowNumber == action.windowNumber else { return }
        _ = menuHost?.performContextMenuAction(
            identifier: action.value.kind.identifier, linkURL: action.value.linkURL,
            selectionText: action.value.selectionText)
    }

    @objc private func downloadImage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        menuHost?.downloadImage(from: url)
    }

    private func addCrestActions(_ actions: [BrowserPageContextMenuAction], to menu: NSMenu) {
        guard !actions.isEmpty else { return }
        var items: [NSMenuItem] = []
        let spaceActions = actions.filter(\.isSpaceDestination)
        if !spaceActions.isEmpty {
            let group = NSMenuItem(title: String(localized: "Open Link in Another Space"), action: nil, keyEquivalent: "")
            group.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
            let submenu = NSMenu()
            for action in spaceActions { submenu.addItem(menuItem(for: action)) }
            group.submenu = submenu
            items.append(group)
        }
        items.append(contentsOf: actions.filter { !$0.isSpaceDestination }.map(menuItem(for:)))
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        if menu.items.count > items.count { menu.insertItem(.separator(), at: items.count) }
    }

    private func menuItem(for action: BrowserPageContextMenuAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(performCrestMenuAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = CrestMenuAction(action, windowNumber: window?.windowNumber)
        item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
        return item
    }

    private final class CrestMenuAction: NSObject {
        let value: BrowserPageContextMenuAction
        let windowNumber: Int?

        init(_ value: BrowserPageContextMenuAction, windowNumber: Int?) {
            self.value = value
            self.windowNumber = windowNumber
        }
    }
}

enum BrowserDesktopWebViewMenuPolicy {
    static let searchWebIdentifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierSearchWeb")
    static let openLinkIdentifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenLinkInNewWindow")

    static func removeDefaultSelectionSearch(in menu: NSMenu) {
        if let item = menu.items.first(where: { $0.identifier == searchWebIdentifier }) {
            menu.removeItem(item)
        }
    }

    static func relabelLinkDestination(in menu: NSMenu) {
        menu.items.first { $0.identifier == openLinkIdentifier }?.title =
            String(localized: "Open Link in This Space")
    }

    static let downloadImageIdentifier = NSUserInterfaceItemIdentifier(
        "WKMenuItemIdentifierDownloadImage"
    )

    static func downloadImageItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.identifier == downloadImageIdentifier }
    }

}
