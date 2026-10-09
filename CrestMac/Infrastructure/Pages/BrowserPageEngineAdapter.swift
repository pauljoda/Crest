import AppKit
import Foundation

/// The desktop half of an engine adapter for one page: the wiring the engine
/// needs into the page it hosts, and the page controllers only that engine can
/// build. The engine's binding builds it when the core asks the engine to
/// create a page. `BrowserPage` holds one and reaches its engine only through
/// it and the `BrowserPageEngine` port.
@MainActor
protocol BrowserPageEngineAdapter: EngineHostedPage {
    var engine: any BrowserPageEngine { get }
    /// The page's direct path to its engine: going back, reloading, finding
    /// text, capturing and exporting the page, and carrying Crest's site
    /// decisions to it.
    var enginePage: EnginePage { get }

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

    /// Builds the page's Media Session coordinator: over Crest's bridge in the
    /// page, or over an engine that reports the session itself.
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
    func styleVisitedLinks(history: [HistoryEntryState]) async
    /// Runs when Crest prepares a navigation, before the engine starts it.
    func prepareForNavigation()
    /// Runs after a change to one of the page's site permissions reached the
    /// engine, so bridges the adapter runs inside the page follow it.
    func sitePermissionDidChange(_ permission: SitePermission, on page: BrowserPage)
    func setPrivateBrowsing(_ isPrivate: Bool)
}

/// The page's PiP lifecycle follows tab presentation, regardless of which
/// engine owns the video and its floating window. The controller asks for
/// automatic entry as its tab leaves the screen, and withdraws a request still
/// pending as the tab returns. A video already floating returns to the page
/// because the core ends it once a window shows the page again.
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
    /// A document in the page asked to share the screen; the person chooses
    /// one of the offer's tabs, or a window or display.
    case shareSourcesOffered(BrowserShareSourceOffer)
    /// The request the offer `shareID` asked about ended first.
    case shareSourcesWithdrawn(shareID: UUID)
    /// The page left the screen, as switching to another tab takes it off.
    case leftScreen
    /// The page's part in tab sharing changed: shared by another page, or
    /// sharing another tab.
    case tabSharingChanged(shared: Bool, sharing: Bool)
    case mediaSession(BrowserMediaSessionPageEvent)
    case contentFullscreenChanged(Bool)
    case userActivity
    case linkHovered(URL?)
    case popupBlocked(pageURL: URL)
    /// A document in the page posted a notification through an engine that
    /// hosts the Notifications API itself.
    case webNotificationPosted(WebNotificationPosted)
    /// The page's document closed a notification it posted.
    case webNotificationClosed(notificationID: String)
    /// The engine kept a link in the page for the Peek the core chose, with
    /// the link it staged for the Peek's first load, if any.
    case peekRequested(URL, decision: LinkNavigationDecision, stagedLink: BrowserEngineNavigation?)
    /// An icon the engine fetched. `source` names the document it belongs
    /// to; nil means the current one.
    case favicon(Data?, source: URL?)
    case developerPanelClosed
    /// The engine closed the page on its own authority, as an extension's
    /// `chrome.tabs.remove` does. The core already closed what owned it.
    case closedByEngine
    case creationFailed(message: String)
}
