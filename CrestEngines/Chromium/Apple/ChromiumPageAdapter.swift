#if CREST_CHROMIUM_HOST
import AppKit

/// The desktop Chromium adapter for one page. The engine reports its page
/// through `ChromiumNativePage`'s observer and handlers; this decodes those
/// reports into the page's engine-neutral events and link actions.
@MainActor
final class ChromiumPageAdapter: BrowserPageEngineAdapter {
    // MARK: - Variables

    let native: ChromiumNativePage
    private weak var page: BrowserPage?
    var engine: any BrowserPageEngine { native }
    var engineIdentifier: String? { native.id }

    /// The engine reports hovered links itself.
    private(set) lazy var linkHover: BrowserLinkHoverController? =
        BrowserLinkHoverController(contentView: native.nativeView)
    private(set) lazy var linkDrag: BrowserLinkDragController? = BrowserLinkDragController(
        nativeView: native.nativeView,
        context: { [weak self] in self?.page?.navigationContext },
        handle: { [weak self] event in self?.page?.handleLinkDrag(event) })
    // Chromium presents Picture in Picture, favicons and its error pages
    // itself; reader and content blocking are unavailable.
    var pictureInPicture: BrowserPictureInPicturePageController? { nil }
    var readerModeSession: BrowserReaderModeSession? { nil }
    var faviconSession: BrowserFaviconSession? { nil }
    var isContentBlockingActive: Bool { false }
    /// Fills go through the engine's content scripting.
    var credentialEvaluator: BrowserCredentialSession.Evaluate? { nil }

    // MARK: - Initializers

    init(_ native: ChromiumNativePage) { self.native = native }

    // MARK: - Actions - Lifecycle

    func makeMediaSessionCoordinator(
        for page: BrowserPage,
        store: BrowserMediaSessionStore
    ) -> BrowserMediaSessionPageCoordinator? { nil }

    func attach(to page: BrowserPage, allowsCredentialAccess: Bool) {
        self.page = page
        native.permissionHandler = { [weak page] permission, origin, topLevelOrigin in
            await page?.resolveEngineSitePermission(permission, origin: origin, topLevelOrigin: topLevelOrigin) ?? 4
        }
        native.observer = { [weak page] name, values in
            guard let event = ChromiumPageEvent(rawValue: name)?.pageEvent(values) else { return }
            page?.receive(event)
        }
        native.linkHandler = { [weak page] name, destination, label in
            guard let page, let action = ChromiumLinkAction(rawValue: name) else { return false }
            return page.performEngineLinkAction(action.pageAction, destination: destination, label: label)
        }
        native.protectedLinkHandler = { [weak page] destination in
            page?.protectedLinkAction(to: destination)
        }
        native.modifiedLinkHandler = { [weak page, weak native] destination, modifiers, token in
            guard let page else { return (.navigate, nil) }
            return page.modifiedLinkDecision(
                to: destination, modifiers: BrowserEngineLinkModifiers(rawValue: modifiers),
                navigationToken: token, discard: { native?.discardNavigation(token) })
        }
        linkDrag?.observeNativeMouseDown()
    }

    func detach(from page: BrowserPage) { native.dispose() }

    func setPrivateBrowsing(_ isPrivate: Bool) { native.isPrivateBrowsing = isPrivate }
    func adoptEngineCreatedPage(_ token: String) -> Bool { native.adopt(token) }

    // MARK: - Actions - Engine-owned services

    /// Chromium's page view takes focus through its own responder chain.
    func install(_ focusRestoration: BrowserWebFocusRestorationController) {}
    /// The engine reports input as a `user_activity` event.
    func monitorUserActivity(for page: BrowserPage) {}
    /// Chromium styles visited links from its own history.
    func styleVisitedLinks(history: [BrowserHistoryEntry]) async {}
    func prepareForNavigation() {}
}

/// The page events the engine host reports, in the host's spelling.
private enum ChromiumPageEvent: String {
    case navigationStarted = "navigation_started"
    case changed
    case infoBarAdded = "infobar_added"
    case infoBarRemoved = "infobar_removed"
    case mediaSession = "media_session"
    case userActivity = "user_activity"
    case linkHover = "link_hover"
    case popupBlocked = "popup_blocked"
    case favicon
    case developerPanel = "developer_panel"
    case closed
    case creationFailed = "creation_failed"
    case openRequested = "open_requested"

    /// Decodes the event's values, or nil when they do not describe one.
    func pageEvent(_ values: [String: Any]) -> BrowserPageEngineEvent? {
        let url = (values["url"] as? String).flatMap(URL.init(string:))
        switch self {
        case .navigationStarted: return .navigationStarted
        case .changed: return .stateChanged(Self.state(values, url: url))
        case .infoBarAdded: return BrowserEngineInfoBar(values: values).map { .infoBarAdded($0) }
        case .infoBarRemoved: return .infoBarRemoved(id: values["id"] as? Int)
        case .mediaSession: return values["body"].map { .mediaSession(body: $0) }
        case .userActivity: return .userActivity
        case .linkHover: return .linkHovered(url)
        case .popupBlocked: return url.map { .popupBlocked(pageURL: $0) }
        case .favicon: return url.map { .favicon(values["data"] as? Data, source: $0) }
        case .developerPanel: return .developerPanelClosed
        case .closed: return .closeRequested
        case .creationFailed: return .creationFailed(message: String(localized: "Chromium couldn’t create this page."))
        case .openRequested: return url.map { .openRequested($0) }
        }
    }

    private static func state(_ values: [String: Any], url: URL?) -> BrowserPageEngineState {
        let failure: BrowserPageEngineState.Failure? =
            switch (values["failure"] as? String).flatMap(ChromiumPageFailure.init(rawValue:)) {
            case .processTerminated: .processTerminated
            case .navigationFailed:
                .navigationFailed(BrowserNavigationFailure(
                    chromiumNetError: values["errorCode"] as? Int ?? 0, failingURL: url))
            case nil: nil
            }
        return BrowserPageEngineState(
            url: url,
            title: values["title"] as? String ?? "",
            isLoading: values["isLoading"] as? Bool ?? false,
            hasOnlySecureContent: values["secure"] as? Bool == true,
            themeColor: (values["themeColor"] as? UInt32).map { argb in
                NSColor(
                    srgbRed: CGFloat((argb >> 16) & 0xFF) / 255, green: CGFloat((argb >> 8) & 0xFF) / 255,
                    blue: CGFloat(argb & 0xFF) / 255, alpha: CGFloat((argb >> 24) & 0xFF) / 255)
            },
            canGoBack: values["canGoBack"] as? Bool ?? false,
            canGoForward: values["canGoForward"] as? Bool ?? false,
            failure: failure,
            committed: values["committed"] as? Bool == true
        )
    }
}

/// A failure a `changed` report names. Other values, such as the notice a
/// stale staged link carries, are not failures of the page's own navigation.
private enum ChromiumPageFailure: String {
    case processTerminated = "process_terminated"
    case navigationFailed = "navigation_failed"
}

/// The link actions the engine's own context menu and drag ask about.
private enum ChromiumLinkAction: String {
    case canSearch = "can_search"
    case search
    case canPeek = "can_peek"
    case peek
    case canSplit = "can_split"
    case split
    case drag

    var pageAction: BrowserEngineLinkAction {
        switch self {
        case .canSearch: .canSearch
        case .search: .search
        case .canPeek: .canPeek
        case .peek: .peek
        case .canSplit: .canSplit
        case .split: .split
        case .drag: .drag
        }
    }
}

/// Builds each page's Chromium adapter with the host commands the
/// composition supplies once it exists.
@MainActor
final class ChromiumPageEngines {
    // MARK: - Variables

    weak var hostCommands: (any BrowserEngineHostCommands)?

    // MARK: - Actions - Pages

    func make(profileID: UUID) -> any BrowserPageEngineAdapter {
        ChromiumPageAdapter(ChromiumNativePage(profileID: profileID, hostCommands: hostCommands))
    }
}

extension BrowserPage {
    /// The Chromium page behind this page, or nil when another engine hosts it.
    var chromiumPage: ChromiumNativePage? { (engineAdapter as? ChromiumPageAdapter)?.native }
}

extension BrowserEnginePageAdoption {
    /// Decodes the engine host's adoption offer; nil when it names no page.
    init?(chromiumValues values: [String: Any]) {
        guard let token = values["adoptionId"] as? String,
            let profileID = (values["profileId"] as? String).flatMap(UUID.init(uuidString:))
        else { return nil }
        self.init(
            token: token,
            profileID: profileID,
            sourcePageID: values["sourcePageId"] as? String,
            windowID: (values["windowId"] as? String).flatMap(UUID.init(uuidString:)).map(BrowserWindowID.init(rawValue:)),
            spaceID: (values["spaceId"] as? String).flatMap(UUID.init(uuidString:)).map(SpaceID.init(rawValue:)),
            url: (values["url"] as? String).flatMap(URL.init(string:)),
            foreground: values["foreground"] as? Bool ?? true
        )
    }
}
#endif
