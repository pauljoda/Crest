import AppKit
import Foundation

/// The desktop half of an engine adapter for one page: the wiring the engine
/// needs into the page it hosts, and the page controllers only that engine can
/// build. The engine's binding builds it when the core asks the engine to
/// create a page. `BrowserPage` holds one and reaches its engine only through
/// it and the `BrowserPageEngine` port.
@MainActor
protocol BrowserPageEngineAdapter: AnyObject {
    var engine: any BrowserPageEngine { get }

    var linkHover: BrowserLinkHoverController? { get }
    var linkDrag: BrowserLinkDragController? { get }
    var pictureInPicture: (any BrowserPagePictureInPictureController)? { get }
    var readerModeSession: BrowserReaderModeSession? { get }
    var faviconSession: BrowserFaviconSession? { get }
    var isContentBlockingActive: Bool { get }
    /// Tells the core what the page's engine shows and what its navigations
    /// do, once the adapter is attached to its page.
    var reporter: EnginePageReporter? { get }
    /// Evaluates a credential fill in the document that asked for it, for an
    /// engine whose bridges are not installed through `contentScripting`.
    var credentialEvaluator: BrowserCredentialSession.Evaluate? { get }

    /// Builds the Media Session coordinator for an engine whose own bridge
    /// reports it; nil when the engine reports it through `mediaSessionTransport`.
    func makeMediaSessionCoordinator(
        for page: BrowserPage,
        store: BrowserMediaSessionStore
    ) -> BrowserMediaSessionPageCoordinator?
    /// Wires the engine's delegates, bridges and observers to `page`, once.
    func attach(to page: BrowserPage, allowsCredentialAccess: Bool)
    /// Releases everything `attach` installed. The page is going away.
    func detach(from page: BrowserPage)

    /// Lets the engine view take part in restoring the page's editing focus.
    func install(_ focusRestoration: BrowserWebFocusRestorationController)
    /// Starts reporting the person's input in the page as `.userActivity`.
    func monitorUserActivity(for page: BrowserPage)
    func styleVisitedLinks(history: [BrowserHistoryEntry]) async
    /// Runs when Crest prepares a navigation, before the engine starts it.
    func prepareForNavigation()
    /// Runs after a change to one of the page's site permissions reached the
    /// engine, so bridges the adapter runs inside the page follow it.
    func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage)
    func setPrivateBrowsing(_ isPrivate: Bool)
    /// Takes over a page the engine created itself, named by `token`.
    func adoptEngineCreatedPage(_ token: String) -> Bool
}

/// The page's PiP lifecycle follows tab presentation, regardless of which
/// engine owns the video and its floating window.
@MainActor
protocol BrowserPagePictureInPictureController: AnyObject {
    var canRestoreSource: Bool { get }
    var protectsPageResidency: Bool { get }
    func leaveTab()
    func returnToTab()
    func navigationDidCommit()
    func nativePresentationDidChange(isActive: Bool)
    func invalidate()
}

extension BrowserPagePictureInPictureController {
    var canRestoreSource: Bool { false }
    var protectsPageResidency: Bool { false }
    func navigationDidCommit() {}
    func nativePresentationDidChange(isActive: Bool) {}
}

/// Something the engine observed about its page that the page presents or
/// acts on. What the page shows, such as its address, title, loading and
/// security, reaches the core through the adapter's `reporter` instead.
enum BrowserPageEngineEvent {
    case navigationStarted
    /// The document's address changed from `from` to `to`.
    case urlChanged(from: URL?, to: URL?)
    case titleChanged
    case progressChanged(Double)
    case themeColorChanged(NSColor?)
    /// The engine's back-forward list changed.
    case historyChanged
    /// An engine that reports its own navigations says whether the page is
    /// loading; each report that it is not ends the navigation in progress.
    case loadingChanged(Bool)
    /// An engine that reports its own navigations committed a new document at
    /// the address, which finished too unless it still loads.
    case navigationCommitted(URL?, isLoading: Bool)
    /// An engine that reports its own navigations failed one; its reporter
    /// told the core why.
    case navigationFailed
    /// An engine that reports its own navigations lost the page's content
    /// process.
    case webContentProcessTerminated
    case infoBarAdded(BrowserEngineInfoBar)
    case infoBarRemoved(id: Int?)
    case mediaSession(body: Any)
    case contentFullscreenChanged(Bool)
    case userActivity
    case linkHovered(URL?)
    case popupBlocked(pageURL: URL)
    /// An icon the engine fetched. `source` names the document it belongs
    /// to; nil means the current one.
    case favicon(Data?, source: URL?)
    case developerPanelClosed
    case closeRequested
    case creationFailed(message: String)
}
