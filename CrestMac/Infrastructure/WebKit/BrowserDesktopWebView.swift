import AppKit
import WebKit

@MainActor
final class BrowserDesktopWebView: WKWebView {
    // MARK: - Static Variables

    private static let displayingPDFSelector = NSSelectorFromString("_isDisplayingPDF")
    private static let pdfMagnificationRange = 0.25...5.0

    // MARK: - Variables

    /// The page that owns this view. Weak because the page owns it.
    weak var menuHost: (any BrowserDesktopWebViewMenuHost)?
    /// The page-owned record of this view's public AppKit editing responder.
    weak var focusRestoration: BrowserWebFocusRestorationController?
    weak var linkHover: BrowserLinkHoverController?
    weak var linkDrag: BrowserLinkDragController?

    // MARK: - Actions - Input

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.intersection([.control, .command, .option, .shift]) == .control,
            event.scrollingDeltaY.isFinite, event.scrollingDeltaY != 0,
            event.momentumPhase.isEmpty,
            responds(to: Self.displayingPDFSelector),
            value(forKey: NSStringFromSelector(Self.displayingPDFSelector)) as? Bool == true
        else {
            super.scrollWheel(with: event)
            return
        }
        // WebKit scrolls Ctrl+wheel in PDFs; its magnification API preserves the pointer's document position.
        let factor = magnification * exp(event.scrollingDeltaY * 0.01)
        let lowerBound = min(magnification, Self.pdfMagnificationRange.lowerBound)
        let upperBound = max(magnification, Self.pdfMagnificationRange.upperBound)
        let bounded = min(max(factor, lowerBound), upperBound)
        setMagnification(bounded, centeredAt: convert(event.locationInWindow, from: nil))
    }

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

    // MARK: - Actions - Menus

    /// Adds Crest's actions ahead of WebKit's native and extension items.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if menuHost?.opensLinksInCurrentSpace == true {
            BrowserDesktopWebViewMenuPolicy.relabelLinkDestination(in: menu)
        }
        BrowserDesktopWebViewMenuPolicy.removeDefaultSelectionSearch(in: menu)
        guard let menuHost, let context = menuHost.takeMenuContext() else { return }
        BrowserPageContextMenu(
            actions: menuHost.contextMenuActions(linkURL: context.linkURL, selectionText: context.selectionText),
            host: menuHost, view: self
        ).insert(into: menu)
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

    @objc private func downloadImage(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        menuHost?.downloadImage(from: url)
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

// WebKit's hover observer remains with its adapter. Other native engine views
// use the same host without inheriting WebKit-specific presentation work.
extension BrowserDesktopWebView: BrowserNativePageSurfaceLifecycle {
    func didAttach(to host: BrowserWebHostView) { linkHover?.attach(to: host) }
    func willDetach(from host: BrowserWebHostView) { linkHover?.detach(from: host) }
}
