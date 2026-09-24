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

/// Something the engine observed about its page. The WebKit adapter reports
/// individual property changes; an engine that reports a navigation snapshot
/// delivers `.stateChanged`.
enum BrowserPageEngineEvent {
    case navigationStarted
    case stateChanged(BrowserPageEngineState)
    case urlChanged(URL?)
    case titleChanged(String?)
    case progressChanged(Double)
    case loadingChanged(Bool)
    case securityStateChanged(BrowserPageSecurityState)
    case themeColorChanged(NSColor?)
    case historyChanged
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

/// One report of a page's navigation state from an engine that keeps it.
struct BrowserPageEngineState {
    enum Failure {
        case processTerminated
        case navigationFailed(BrowserNavigationFailure)
    }

    var url: URL?
    var title: String
    var isLoading: Bool
    var security: BrowserPageSecurityState
    var themeColor: NSColor?
    var canGoBack: Bool
    var canGoForward: Bool
    var failure: Failure?
    /// True when this report ends a navigation that committed a document.
    var committed: Bool
}
