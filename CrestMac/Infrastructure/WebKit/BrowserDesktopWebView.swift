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

    /// Routes search and Space destinations through Crest in WebKit's native menu.
    ///
    /// AppKit calls this with the finished menu, which is the one moment a
    /// link-aware item can be added: WebKit's items stay exactly as WebKit
    /// ordered them, and the destination comes from the `contextmenu` report
    /// the content bridge posted a moment earlier rather than from a second
    /// hit test of Crest's own.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if menuHost?.opensLinksInCurrentSpace == true {
            BrowserDesktopWebViewMenuPolicy.relabelLinkDestination(in: menu)
        }
        let context = menuHost?.takeMenuContext()
        replaceSelectionSearch(in: menu, with: context?.selectionSearch)
        guard let context else { return }
        if let destinations = context.linkDestinations {
            addSpaceDestinations(destinations, to: menu)
        }
        if let imageDownloadURL = context.imageDownloadURL,
            let item = BrowserDesktopWebViewMenuPolicy.downloadImageItem(in: menu)
        {
            item.target = self
            item.action = #selector(downloadImage(_:))
            item.representedObject = imageDownloadURL
        }
        BrowserDesktopWebViewMenuPolicy.append(
            menuHost?.extensionMenuItems(for: context) ?? [],
            to: menu
        )
        guard let destination = context.splitViewLinkDestination else { return }
        let item = NSMenuItem(
            title: String(localized: "Open Link in Split View"),
            action: #selector(openLinkInSplitView(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.representedObject = destination
        BrowserDesktopWebViewMenuPolicy.append([item], to: menu)
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

    private func replaceSelectionSearch(in menu: NSMenu, with destination: BrowserSelectionSearchDestination?) {
        guard
            let item = menu.items.first(where: {
                $0.identifier == BrowserDesktopWebViewMenuPolicy.searchWebIdentifier
            })
        else { return }
        // Never leave the macOS service action behind when this menu has no
        // fresh selection or its source Space is no longer available.
        guard let destination, let window else {
            menu.removeItem(item)
            return
        }
        item.title = String(localized: "Search with \(destination.provider.title)")
        item.target = self
        item.action = #selector(openLinkInSpace(_:))
        item.representedObject = LinkSpaceAction(
            url: destination.url, source: destination.source,
            destination: BrowserSpaceRuntimeAssignment(
                spaceID: destination.source.spaceID, profileID: destination.source.profileID
            ),
            windowNumber: window.windowNumber
        )
    }

    private func addSpaceDestinations(_ destinations: BrowserDesktopLinkDestinations, to menu: NSMenu) {
        guard !destinations.spaces.isEmpty, let window else { return }
        let item = NSMenuItem(
            title: String(localized: "Open Link in Another Space"), action: nil, keyEquivalent: ""
        )
        let submenu = NSMenu()
        for space in destinations.spaces {
            let choice = NSMenuItem(title: space.name, action: #selector(openLinkInSpace(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = LinkSpaceAction(
                url: destinations.url, source: destinations.source,
                destination: BrowserSpaceRuntimeAssignment(space: space),
                windowNumber: window.windowNumber
            )
            submenu.addItem(choice)
        }
        item.submenu = submenu
        let sourceIndex = menu.items.firstIndex { $0.identifier == BrowserDesktopWebViewMenuPolicy.openLinkIdentifier }
        menu.insertItem(item, at: sourceIndex.map { $0 + 1 } ?? 0)
    }

    @objc private func openLinkInSpace(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? LinkSpaceAction,
            window?.windowNumber == action.windowNumber
        else { return }
        menuHost?.openLink(action.url, from: action.source, in: action.destination)
    }

    private struct LinkSpaceAction {
        let url: URL
        let source: BrowserTabRuntimeAssignment
        let destination: BrowserSpaceRuntimeAssignment
        let windowNumber: Int
    }
}

enum BrowserDesktopWebViewMenuPolicy {
    static let searchWebIdentifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierSearchWeb")
    static let openLinkIdentifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenLinkInNewWindow")

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

    static func append(_ items: [NSMenuItem], to menu: NSMenu) {
        guard !items.isEmpty else { return }
        if let last = menu.items.last, !last.isSeparatorItem {
            menu.addItem(.separator())
        }
        for item in items {
            menu.addItem(item)
        }
    }
}
