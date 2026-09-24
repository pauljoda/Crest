import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

#if CREST_PHYSICAL_VALIDATION
    import CryptoKit
    import OSLog
    import Security
#endif

@Observable
@MainActor
final class MobileBrowserPage: NSObject, BrowserMediaSessionCommandEndpoint, BrowserPagePermissionProviding {
    var opensModifiedLinksInForeground = false
    /// The core's page, which `release(keepingState:)` ends.
    @ObservationIgnored let corePage: CorePage
    private(set) var tabID: TabID
    let spaceID: SpaceID
    let profileID: UUID
    let webView: WKWebView
    var webKitView: WKWebView? { webView }
    // iOS composes one engine. Naming its type here keeps the page port in
    // play everywhere it is used while removing the force-cast the history
    // accessor needed to reach a WebKit-only service.
    @ObservationIgnored lazy var pageEngine = BrowserWebKitPageEngine(webView: webView)

    /// The store that owns this page. Weak because the store owns the page.
    weak var host: (any MobileBrowserPageHosting)?

    /// True when web content opened this page through `window.open()`. It gates
    /// `window.close()`, which may only close what script itself opened.
    var wasOpenedAsPopup = false

    /// True from adoption until WebKit starts the popup's own navigation. WebKit
    /// drives an adopted popup, so nothing else may load it in that window —
    /// loading it here is what breaks `window.opener` and `document.write`.
    var isAwaitingPopupNavigation = false

    var url: URL?
    private(set) var title: String?
    private(set) var estimatedProgress = 0.0
    private(set) var isLoading = false
    private(set) var faviconData: Data?
    private(set) var themeColor: UIColor?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    var committedNavigationCount = 0
    private(set) var completedNavigationCount = 0
    private(set) var navigationFailure: BrowserNavigationFailure?
    var blockedPopupState = BrowserBlockedPopupPageState()
    var pendingServerTrustIdentity: BrowserServerTrustIdentity?
    var pendingNavigationURL: URL?
    var navigationHistory: BrowserPageNavigationHistory {
        get { pageEngine.history }
        set { pageEngine.history = newValue }
    }
    private(set) var showsProcessFailure = false
    var isFindPresented: Bool { findSession.isPresented }
    var findQuery: String { findSession.query }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    var findFocusRequest: Int { findSession.focusRequest }
    private(set) var pageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel
    let translation = BrowserPageTranslation()
    var readerModeState: BrowserReaderModeState { readerModeSession.state }
    var isContentBlockingActive: Bool { contentRuleSession.isActive }
    private(set) var isRequestingDesktopSite = false
    var isCredentialAccessEnabled: Bool { credentialSession.isEnabled }
    /// True once iOS reclaimed this page's web-content process while it was off
    /// screen. Selecting the tab again is what brings the page back.
    private(set) var needsWebContentRestore = false
    var credentialFillRequest: BrowserCredentialFillRequest? { credentialState.fillRequest }
    var credentialSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.saveCandidate }
    var hasActiveLinkActivationBridge: Bool { linkActivationMessageProxy != nil }

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let pullToRefreshControl = UIRefreshControl()
    @ObservationIgnored let linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored private let openModifiedLink: MobileBrowserPageStore.ModifiedLinkOpener
    @ObservationIgnored let downloadCenter: BrowserDownloadCenter
    let sitePermissionRequests = BrowserPagePermissionController()
    /// Carries Crest's site permission decisions to the page as they change.
    @ObservationIgnored lazy var sitePermissionSession: BrowserPageSitePermissionSession = {
        let session = BrowserPageSitePermissionSession(
            engine: pageEngine, permissionCenter: permissionCenter, spaceID: spaceID)
        session.siteURL = { [weak self] in self?.pageEngine.currentURL ?? self?.url }
        session.siteDecisionDidChange = { [weak self] permission in
            if permission == .popups { self?.synchronizePopupPermission() }
        }
        return session
    }()
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let popupCoordinator: BrowserPopupCoordinator
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored var appInitiatedURL: URL?
    @ObservationIgnored private(set) var appInitiatedNavigationCount = 0
    @ObservationIgnored let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored var contextMenuPreviewCommit: (() -> Void)?
    @ObservationIgnored var navigationContext: BrowserPageNavigationContext?
    @ObservationIgnored var activeNavigation: WKNavigation?
    @ObservationIgnored let spaceName: String
    @ObservationIgnored private var processRecovery = BrowserProcessRecovery()
    @ObservationIgnored private let findSession = BrowserFindSession()
    @ObservationIgnored lazy var readerModeSession = BrowserReaderModeSession(
        document: BrowserWebKitReaderModeDocument(webView: webView, translation: translation)
    )
    @ObservationIgnored lazy var faviconSession = BrowserFaviconSession(
        document: BrowserWebKitFaviconDocument(webView: webView, profileID: profileID),
        policy: .immediate,
        receive: { [weak self] in self?.faviconData = $0 }
    )
    @ObservationIgnored private let credentialSession: BrowserCredentialSession
    var credentialState: BrowserCredentialPageState<BrowserCredentialSession.FillTarget> {
        credentialSession.state
    }
    @ObservationIgnored private var credentialMessageProxy: BrowserCredentialScriptMessageProxy?
    @ObservationIgnored private var linkActivationMessageProxy: MobileLinkActivationScriptMessageProxy?
    @ObservationIgnored var linkActivationSourceStore = MobileLinkActivationSourceStore()
    @ObservationIgnored var downloadSourceStore = BrowserDownloadSourceStore()
    @ObservationIgnored private var userActivityMessageProxy: BrowserUserActivityScriptMessageProxy?
    @ObservationIgnored private var geolocationMessageProxy: BrowserGeolocationScriptMessageProxy?
    @ObservationIgnored private var blockedPopupMessageProxy: BrowserBlockedPopupScriptMessageProxy?
    @ObservationIgnored private var mediaSessionMessageProxy: BrowserMediaSessionScriptMessageProxy?
    @ObservationIgnored var mediaSessionCoordinator: BrowserMediaSessionPageCoordinator?
    @ObservationIgnored var geolocationCoordinator: BrowserGeolocationCoordinator?
    @ObservationIgnored private var userActivityHandler: (() -> Void)?
    @ObservationIgnored let httpAuthenticationSession: BrowserHTTPAuthenticationSession
    @ObservationIgnored private let contentRuleSession: BrowserPageContentRuleSession

    /// False when this page shares the opener's `WKUserContentController`, which
    /// every popup does. Installing the same script message handler twice on it
    /// throws, and removing one would strip it from the opener.
    @ObservationIgnored private let ownsUserContentController: Bool
    @ObservationIgnored private var defaultPageZoom: CGFloat
    @ObservationIgnored private var hasTemporaryPageZoomOverride = false

    var displayURL: URL? {
        navigationFailure?.failingURL ?? pendingNavigationURL ?? url
    }

    init(
        corePage: CorePage,
        tab: BrowserTab,
        space: BrowserSpace,
        downloadCenter: BrowserDownloadCenter = BrowserDownloadCenter(),
        permissionCenter: BrowserSitePermissionCenter = BrowserSitePermissionCenter(),
        geolocationService: any BrowserGeolocationServicing =
            BrowserGeolocationSystemService(),
        recoverGeolocationSystemAuthorization:
            BrowserGeolocationCoordinator.RecoverSystemAuthorization? = nil,
        serverTrustOverrides: BrowserServerTrustOverrideStore = BrowserServerTrustOverrideStore(),
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        websiteDataStore: WKWebsiteDataStore? = nil,
        adoptedConfiguration: WKWebViewConfiguration? = nil,
        contentRuleList: WKContentRuleList? = nil,
        contentRuleLists: [WKContentRuleList] = [],
        allowsCredentialAccess: Bool = true,
        isCredentialAccessEnabled: Bool = true,
        defaultPageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel,
        loadsInitialURL: Bool = true,
        loadHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.LoadCredential = { _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.SaveCredential = { _ in },
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
        openNewTab: @escaping (URL) -> Void,
        openModifiedLink: @escaping MobileBrowserPageStore.ModifiedLinkOpener = {
            _, _, _ in nil
        },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        opensExternalURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        self.corePage = corePage
        tabID = tab.id
        spaceID = space.id
        profileID = space.profile.id
        url = tab.url
        faviconData = tab.displayFaviconData
        self.downloadCenter = downloadCenter
        self.permissionCenter = permissionCenter
        self.serverTrustOverrides = serverTrustOverrides
        self.linkDestinationHost = linkDestinationHost
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        contentRuleSession = BrowserPageContentRuleSession(
            ruleLists: contentRuleLists,
            additionalRuleList: contentRuleList
        )
        spaceName = space.name
        navigationContext = BrowserPageNavigationContext(
            tab: tab,
            spaceID: space.id,
            profileID: space.profile.id,
            automaticallyOpensPeek: BrowserLinkPreferenceStore.shared
                .preferences.automaticallyOpensPeek
        )
        navigationDecider = BrowserNavigationDecider()
        // Built before the popup coordinator so a popup whose destination belongs
        // to another application can be routed into the same consent path an
        // ordinary external-scheme navigation takes.
        let externalSchemeCoordinator = BrowserExternalSchemeCoordinator(
            spaceID: space.id,
            spaceName: space.name,
            permissionCenter: permissionCenter,
            prompt: { origin, destinationURL, requestedSpaceName in
                await MobileBrowserDialogPresenter.presentExternalApplicationPermission(
                    origin: origin,
                    destinationURL: destinationURL,
                    spaceName: requestedSpaceName
                )
            },
            opensExternalURL: opensExternalURL
        )
        self.externalSchemeCoordinator = externalSchemeCoordinator
        popupCoordinator = BrowserPopupCoordinator(
            openNewTab: openNewTab,
            handOffExternalScheme: { destinationURL, trigger, origin in
                externalSchemeCoordinator.handOff(
                    destinationURL: destinationURL,
                    trigger: trigger,
                    origin: origin
                )
            }
        )
        let normalizedDefaultPageZoom = BrowserPageZoomPolicy.normalizedDefault(
            defaultPageZoom
        )
        self.defaultPageZoom = normalizedDefaultPageZoom
        pageZoom = normalizedDefaultPageZoom
        let httpAuthenticationSession = BrowserHTTPAuthenticationSession(
            spaceID: space.id,
            allowsCredentialSaving: allowsCredentialAccess
                && isCredentialAccessEnabled,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential
        )
        self.httpAuthenticationSession = httpAuthenticationSession
        credentialSession = BrowserCredentialSession(
            spaceID: space.id,
            core: downloadCenter.core,
            supportsAccess: allowsCredentialAccess,
            isEnabled: isCredentialAccessEnabled,
            httpAuthentication: httpAuthenticationSession
        )

        // WebKit hands popups a configuration derived from their opener's, and it
        // has to be used exactly as given. That copy also shares the opener's
        // user content controller, so its scripts, rule lists, and message
        // handlers are already installed: adding them again throws.
        ownsUserContentController = adoptedConfiguration == nil
        let configuration: WKWebViewConfiguration
        if let adoptedConfiguration {
            configuration = adoptedConfiguration
        } else {
            // The shared factory owns every setting both platforms want — the
            // inactive scheduling policy above all, which is what lets WebKit
            // suspend a resident background tab on the platform that jetsams.
            // Only what is genuinely mobile is decorated on top of it.
            var installedLinkActivationProxy: MobileLinkActivationScriptMessageProxy?
            configuration = BrowserPageConfiguration.make(
                for: space.profile,
                websiteDataStore: websiteDataStore,
                contentRuleLists: contentRuleSession.ruleLists,
                preferredContentMode: .recommended
            ) { configuration in
                configuration.allowsInlineMediaPlayback = true
                configuration.allowsPictureInPictureMediaPlayback = true
                configuration.mediaTypesRequiringUserActionForPlayback = .all
                configuration.userContentController.addUserScript(
                    MobileMediaPlaybackPolicy.inlineVideoScript
                )
                installedLinkActivationProxy = MobileLinkActivationContentBridge.install(
                    in: configuration.userContentController
                )
            }
            linkActivationMessageProxy = installedLinkActivationProxy
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.underPageBackgroundColor = .clear

        super.init()
        if normalizedDefaultPageZoom != BrowserPageZoomPolicy.defaultLevel {
            webView.pageZoom = normalizedDefaultPageZoom
        }
        #if DEBUG
            // iOS ships no developer tooling of its own, so an inspectable
            // release web view would be attack surface and nothing else: any
            // trusted Mac could attach Safari's Web Inspector to a session.
            webView.isInspectable = true
        #endif
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        if let mediaSessionStore {
            let coordinator = BrowserMediaSessionPageCoordinator(
                webView: webView,
                endpoint: self,
                store: mediaSessionStore,
                owner: { [weak self] in
                    guard let self else { return nil }
                    return BrowserTabRuntimeAssignment(
                        tabID: tabID,
                        spaceID: spaceID,
                        profileID: profileID
                    )
                },
                fallbackTitle: { [weak self] in
                    guard let self else { return nil }
                    return self.navigationContext?.mediaSessionOwnerTitle(
                        observedPageTitle: self.title
                    ) ?? BrowserTab.resolvedCustomTitle(self.title)
                }
            )
            mediaSessionCoordinator = coordinator
            if ownsUserContentController {
                mediaSessionMessageProxy =
                    BrowserMediaSessionContentBridge.install(
                        in: webView.configuration.userContentController
                    ) { [weak self] message in
                        self?.receiveMediaSessionMessage(message)
                    }
            }
        }
        linkActivationMessageProxy?.receive = { [weak self] message in
            self?.receiveLinkActivationMessage(message)
        }
        geolocationCoordinator = BrowserGeolocationCoordinator(
            webView: webView,
            permissionCenter: permissionCenter,
            service: geolocationService,
            spaceID: space.id,
            spaceName: space.name,
            prompt: { [weak self] origin, topLevelURL, requestedSpaceName in
                guard let self else { return .denyOnce }
                return await self.sitePermissionRequests.response(
                    to: .location, origin: origin,
                    topLevelOrigin: topLevelURL.flatMap(BrowserSiteOrigin.init(url:)) ?? origin,
                    spaceName: requestedSpaceName
                )
            },
            recoverSystemAuthorization:
                recoverGeolocationSystemAuthorization
                ?? {
                    await MobileBrowserDialogPresenter
                        .recoverGeolocationSystemAuthorization()
                }
        )
        if ownsUserContentController {
            blockedPopupMessageProxy = BrowserBlockedPopupContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveBlockedPopupMessage(message)
            }
            geolocationMessageProxy = BrowserGeolocationContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveGeolocationMessage(message)
            }
        }
        installObservations()
        if allowsCredentialAccess, ownsUserContentController {
            credentialMessageProxy = BrowserCredentialContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveCredentialMessage(message)
            }
        }
        pullToRefreshControl.addTarget(
            self,
            action: #selector(refreshFromPull),
            for: .valueChanged
        )
        webView.scrollView.refreshControl = pullToRefreshControl
        // Observe permission changes from the start, not from the first grant.
        _ = sitePermissionSession

        if loadsInitialURL, let url = tab.url {
            load(url)
        }
    }

    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    func load(_ request: URLRequest) {
        appInitiatedNavigationCount &+= 1
        url = request.url
        appInitiatedURL = request.url
        prepareForNavigation(to: request.url)
        pageEngine.load(request)
    }

    func routeModifiedLink(_ url: URL, selecting: Bool) {
        routeModifiedLink(URLRequest(url: url), selecting: selecting)
    }

    func routeModifiedLink(_ request: URLRequest, selecting: Bool) {
        guard let url = request.url,
            let registration = openModifiedLink(url, spaceID, selecting)
        else { return }
        host?.loadOpenedLink(registration, request: request, selecting: selecting)
    }

    /// WebKit's own opaque per-view session state: the back/forward list and the
    /// scroll position of every entry in it.
    ///
    /// Nil until a document has committed. A web view that never loaded still
    /// answers `interactionState` with an empty session, and archiving that would
    /// replace a real state with one that restores nothing.
    var interactionState: Data? {
        pageEngine.interactionState
    }

    /// Restores a previously archived `interactionState` instead of starting `url`
    /// afresh, and reports whether WebKit took it.
    ///
    /// WebKit performs the navigation itself once the state is installed, so this
    /// replaces `load(_:)` rather than preceding it. Invalid state is discarded
    /// silently by WebKit — no exception, nothing loaded — which is exactly the
    /// signal used here: a web view left without a current back/forward item did
    /// not restore, and the caller falls back to an ordinary load.
    @discardableResult
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        // WebKit owns an adopted popup's first navigation, and an adopted popup
        // has no archived state of its own to restore in the first place.
        guard !isAwaitingPopupNavigation, !wasOpenedAsPopup else { return false }
        self.url = url
        appInitiatedURL = url
        prepareForNavigation(to: url)
        guard pageEngine.restoreInteractionState(state, expecting: url) else {
            pendingNavigationURL = nil
            return false
        }
        return true
    }

    /// Records that web content opened this page and that WebKit still owes it a
    /// navigation. Only a page store adopting a popup calls this.
    func markOpenedAsPopup() {
        wasOpenedAsPopup = true
        isAwaitingPopupNavigation = true
    }

    func monitorUserActivity(_ handler: @escaping () -> Void) {
        userActivityHandler = handler
        guard ownsUserContentController, userActivityMessageProxy == nil else { return }
        userActivityMessageProxy = BrowserUserActivityBridge.install(
            in: webView.configuration.userContentController
        ) { [weak self] in
            self?.userActivityHandler?()
        }
    }

    func styleVisitedLinks(history: [BrowserHistoryEntry]) async {
        await BrowserVisitedLinkStyler.apply(history: history, to: webView)
    }

    func stopMonitoringUserActivity() {
        userActivityHandler = nil
    }

    func adopt(tabID: TabID, tab: BrowserTab) {
        self.tabID = tabID
        updateNavigationContext(tab: tab)
    }

    func updateNavigationContext(
        tab: BrowserTab,
        automaticallyOpensPeek: Bool = true
    ) {
        let previousTitle = navigationContext?.title
        let shouldRefreshAutomaticIcon =
            tab.iconMode.followsPage
            && !tab.hasCurrentAutomaticFavicon
            && webView.url != nil
            && !webView.isLoading
        if faviconData != tab.displayFaviconData
            || navigationContext?.iconMode != tab.iconMode
            || navigationContext?.tabID != tab.id
        {
            faviconSession.invalidate()
            faviconData = tab.displayFaviconData
        }
        navigationContext = BrowserPageNavigationContext(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            automaticallyOpensPeek: automaticallyOpensPeek
        )
        if previousTitle != navigationContext?.title {
            mediaSessionCoordinator?.ownerTitleDidChange()
        }
        if shouldRefreshAutomaticIcon {
            refreshFavicon()
        }
    }

    /// Ends the page: every page ends here, whether its tab closed, it was
    /// unloaded, its Space went, or a transient request let it go. The web view
    /// comes down first, then the core hears the page is gone. `keepingState`
    /// says the owner kept what it needs to bring the page back.
    func release(keepingState: Bool) {
        tearDownWebView()
        corePage.release(keepingState: keepingState)
    }

    private func tearDownWebView() {
        faviconSession.stop()
        sitePermissionSession.resetMediaGrants()
        sitePermissionRequests.setPresentationAvailable(false)
        translation.reset()
        readerModeSession.invalidate()
        mediaSessionCoordinator?.prepareForRemoval()
        downloadCenter.resetAutomaticDownloadSequence(for: pageEngine)
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        for observation in observations {
            observation.invalidate()
        }
        observations.removeAll()
        removeGeolocationRequests()
        guard ownsUserContentController else {
            // A popup shares its opener's content controller. Removing handlers
            // here would silence them for the opener too.
            credentialMessageProxy = nil
            linkActivationMessageProxy = nil
            userActivityMessageProxy = nil
            geolocationMessageProxy = nil
            blockedPopupMessageProxy = nil
            mediaSessionMessageProxy = nil
            mediaSessionCoordinator = nil
            geolocationCoordinator = nil
            userActivityHandler = nil
            return
        }
        if credentialMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserCredentialContentBridge.messageHandlerName,
                    contentWorld: BrowserCredentialContentBridge.contentWorld
                )
        }
        credentialMessageProxy = nil
        if linkActivationMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: MobileLinkActivationContentBridge.messageHandlerName,
                    contentWorld: MobileLinkActivationContentBridge.contentWorld
                )
        }
        linkActivationMessageProxy?.receive = { _ in }
        linkActivationMessageProxy = nil
        if userActivityMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserUserActivityBridge.messageHandlerName,
                    contentWorld: BrowserUserActivityBridge.contentWorld
                )
        }
        userActivityMessageProxy = nil
        if geolocationMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserGeolocationContentBridge.messageHandlerName,
                    contentWorld: BrowserGeolocationContentBridge.contentWorld
                )
        }
        geolocationMessageProxy = nil
        if blockedPopupMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserBlockedPopupContentBridge.messageHandlerName,
                    contentWorld: BrowserBlockedPopupContentBridge.contentWorld
                )
        }
        blockedPopupMessageProxy = nil
        if mediaSessionMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserMediaSessionContentBridge.messageHandlerName,
                    contentWorld: BrowserMediaSessionContentBridge.contentWorld
                )
        }
        mediaSessionMessageProxy = nil
        mediaSessionCoordinator = nil
        geolocationCoordinator = nil
        userActivityHandler = nil
    }

    func reloadOrStop() {
        performReload(.standard)
    }

    func togglePreferredContentMode() {
        isRequestingDesktopSite.toggle()
        webView.configuration.defaultWebpagePreferences.preferredContentMode =
            isRequestingDesktopSite ? .desktop : .recommended
        guard url != nil else { return }
        webView.reloadFromOrigin()
    }

    func applyContentBlocking(
        policy: ContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        contentRuleSession.apply(
            policy: policy,
            balancedRuleLists: balancedRuleLists,
            to: webView,
            reloadsImmediately: activation == .immediately && url != nil
        )
    }

    func retryAfterProcessFailure() {
        processRecovery.reset()
        showsProcessFailure = false
        pageEngine.reload(bypassingCache: false)
    }

    func presentFind() {
        findSession.present(hasLoadedPage: url != nil)
    }

    func dismissFind() {
        findSession.dismiss(using: pageEngine)
    }

    func find(_ query: String, direction: BrowserFindDirection = .forward) {
        findSession.find(query, direction: direction, using: pageEngine)
    }

    @discardableResult
    func zoomIn() -> Bool {
        setTemporaryPageZoom(BrowserPageZoomPolicy.increased(from: pageZoom))
    }

    @discardableResult
    func zoomOut() -> Bool {
        setTemporaryPageZoom(BrowserPageZoomPolicy.decreased(from: pageZoom))
    }

    @discardableResult
    func resetZoom() -> Bool {
        hasTemporaryPageZoomOverride = false
        return setPageZoom(defaultPageZoom)
    }

    @discardableResult
    func applyDefaultPageZoom(_ zoom: CGFloat) -> Bool {
        let normalized = BrowserPageZoomPolicy.normalizedDefault(zoom)
        defaultPageZoom = normalized
        if hasTemporaryPageZoomOverride {
            if BrowserPageZoomPolicy.levelsMatch(pageZoom, normalized) {
                hasTemporaryPageZoomOverride = false
            }
            return false
        }
        return setPageZoom(normalized)
    }

    func refreshReaderModeAvailability() async {
        await readerModeSession.refreshAvailability()
    }

    func setReaderModeActive(_ isActive: Bool) async throws {
        try await readerModeSession.setActive(isActive)
    }

    func toggleReaderMode() {
        readerModeSession.toggle()
    }

    @discardableResult
    func copyPageLink() -> Bool {
        BrowserPageLinkClipboard.copy(url)
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        guard let url else { return false }
        let label = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? (url.host() ?? url.absoluteString) : label
        let escapedLabel =
            resolvedLabel
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        UIPasteboard.general.string = "[\(escapedLabel)](\(url.absoluteString))"
        return true
    }

    func printPage() {
        guard url != nil else { return }
        let controller = UIPrintInteractionController.shared
        let printInfo = UIPrintInfo(dictionary: nil)
        printInfo.outputType = .general
        printInfo.jobName =
            title?.isEmpty == false
            ? title ?? ProductIdentity.name
            : url?.host() ?? ProductIdentity.name
        controller.printInfo = printInfo
        controller.printFormatter = webView.viewPrintFormatter()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.webView.window != nil else { return }
            if UIDevice.current.userInterfaceIdiom == .pad {
                controller.present(
                    from: CGRect(x: self.webView.bounds.maxX - 1, y: 1, width: 1, height: 1),
                    in: self.webView,
                    animated: true,
                    completionHandler: nil
                )
            } else {
                controller.present(animated: true, completionHandler: nil)
            }
        }
    }

    func pdfData() async throws -> Data {
        guard url != nil else { throw BrowserPageExportError.pageUnavailable }
        return try await webView.pdf(configuration: WKPDFConfiguration())
    }

    func exportPDF(to destination: MobileBrowserFileExportDestination) {
        guard url != nil else { return }
        let suggestedFilename = BrowserPageExportPolicy.pdfFilename(title: title, url: url)
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await pdfData()
                try await MobileBrowserDialogPresenter.exportDocument(
                    data,
                    filename: suggestedFilename,
                    to: destination
                )
            } catch {
                MobileBrowserDialogPresenter.presentError(
                    title: "The page couldn’t be exported.",
                    message: error.localizedDescription
                )
            }
        }
    }

    func webArchiveData() async throws -> Data {
        guard url != nil else { throw BrowserPageExportError.pageUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            webView.createWebArchiveData { result in
                continuation.resume(with: result)
            }
        }
    }

    func exportWebArchive(to destination: MobileBrowserFileExportDestination) {
        guard url != nil else { return }
        let suggestedFilename = BrowserPageExportPolicy.webArchiveFilename(
            title: title,
            url: url
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await webArchiveData()
                try await MobileBrowserDialogPresenter.exportDocument(
                    data,
                    filename: suggestedFilename,
                    to: destination
                )
            } catch {
                MobileBrowserDialogPresenter.presentError(
                    title: "The page couldn’t be saved as a web archive.",
                    message: error.localizedDescription
                )
            }
        }
    }

    func dismissCredentialFillRequest() {
        credentialState.dismissFillRequest()
    }

    func dismissCredentialSaveCandidate() {
        credentialState.dismissSaveCandidate()
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        credentialSession.setEnabled(isEnabled)
    }

    func fillCredential(_ credential: BrowserCredential, for requestID: UUID) async throws {
        try await credentialSession.fill(credential, for: requestID, in: webView)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID) async throws {
        try await credentialSession.fillGeneratedPassword(password, for: requestID, in: webView)
    }

    private func installObservations() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    if let url = webView.url {
                        self?.translation.documentURLDidChange(from: self?.url, to: url)
                        self?.url = url
                        self?.refreshNavigationState()
                    }
                    self?.credentialState.didChangeTopLevelURL(to: webView.url ?? self?.url)
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.recordObservedTitle(webView.title)
                    self?.refreshNavigationState()
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.estimatedProgress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.isLoading = webView.isLoading
                    self?.refreshNavigationState()
                    if !webView.isLoading {
                        self?.pullToRefreshControl.endRefreshing()
                    }
                }
            },
            webView.observe(\.themeColor, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    let themeColor = webView.themeColor
                    self?.themeColor = themeColor
                    // A standards-provided theme color owns the browser's
                    // overscroll atmosphere. Nil restores WebKit's derived
                    // html/body background instead of inventing a Crest color.
                    self?.updateUnderPageBackground()
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.refreshNavigationState() }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.refreshNavigationState() }
            },
        ]
    }

    @objc private func refreshFromPull() {
        guard webView.reload() != nil else {
            pullToRefreshControl.endRefreshing()
            return
        }
    }

    func completeNavigation() {
        activeNavigation = nil
        clearNavigationFailure()
        url = webView.url
        recordObservedTitle(webView.title)
        processRecovery.recordSuccessfulNavigation()
        showsProcessFailure = false
        needsWebContentRestore = false
        refreshFavicon()
        publishCompletedNavigation()
    }

    /// The session keeps only the metadata a completed navigation reports, and
    /// `webView.title` can still be empty when WebKit finishes a new document.
    /// Read the settled document title first, then count the completion unless
    /// another navigation has replaced this document meanwhile.
    private func publishCompletedNavigation() {
        let completedURL = webView.url
        let committedNavigation = committedNavigationCount
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            let documentTitle = try? await webView.evaluateJavaScript("document.title") as? String
            guard activeNavigation == nil,
                committedNavigationCount == committedNavigation,
                webView.url == completedURL
            else { return }
            recordObservedTitle(documentTitle?.isEmpty == false ? documentTitle : webView.title)
            completedNavigationCount &+= 1
            updateUnderPageBackground()
        }
    }

    private func recordObservedTitle(_ observedTitle: String?) {
        guard title != observedTitle else { return }
        title = observedTitle
        mediaSessionCoordinator?.ownerTitleDidChange()
    }

    private func refreshFavicon() {
        guard navigationContext?.iconMode.followsPage == true,
            webView.url != nil
        else { return }
        faviconSession.refresh()
    }

    func pullFavicon() async -> Data? {
        await faviconSession.pull()
    }

    var siteThemeIconAccent: BrowserTabIconAccent? {
        guard let themeColor else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard themeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
            alpha > 0
        else { return nil }
        return BrowserTabIconAccent(
            red: Double(red),
            green: Double(green),
            blue: Double(blue)
        )
    }

    /// Reacts to WebKit losing this page's web-content process.
    ///
    /// On iOS this is the routine eviction path, not a crash: the system reclaims a
    /// background tab's process precisely to get its memory back. Reloading such a
    /// page off screen would hand that memory straight back and spend one of the two
    /// automatic reloads the error screen depends on, so an off-screen page is
    /// marked and restored when it is selected again. A page the user is looking at
    /// still recovers immediately.
    func recordWebContentTermination() {
        credentialState.webContentProcessDidTerminate()
        guard isVisible else {
            needsWebContentRestore = true
            return
        }
        switch processRecovery.recordTermination() {
        case .reload:
            webView.reload()
        case .showFailure:
            showsProcessFailure = true
        }
    }

    /// Reloads a page whose web-content process was reclaimed while it was off
    /// screen. The page store calls this as it activates a page.
    func restoreWebContentIfNeeded() {
        guard needsWebContentRestore else { return }
        needsWebContentRestore = false
        webView.reload()
    }

    /// True while this page's web view is in a window, which is what being the
    /// surface the user is looking at amounts to: a resident background tab and a
    /// released Peek are both detached from the view hierarchy.
    private var isVisible: Bool {
        webView.window != nil
    }

    private func setTemporaryPageZoom(_ zoom: CGFloat) -> Bool {
        let changed = setPageZoom(zoom)
        hasTemporaryPageZoomOverride = !BrowserPageZoomPolicy.levelsMatch(
            pageZoom,
            defaultPageZoom
        )
        return changed
    }

    private func setPageZoom(_ zoom: CGFloat) -> Bool {
        guard zoom != pageZoom else {
            return false
        }
        pageZoom = zoom
        pageEngine.setZoom(zoom)
        return true
    }

    func prepareForNavigation(to url: URL?) {
        sitePermissionSession.resetMediaGrants()
        sitePermissionRequests.cancelAll()
        translation.reset()
        readerModeSession.invalidate()
        mediaSessionCoordinator?.prepareForNavigation()
        beginBlockedPopupNavigation()
        synchronizePopupPermission(for: url)
        faviconSession.invalidate()
        pendingNavigationURL = url
        clearNavigationFailure(preservingPendingURL: true)
    }

    func updateUnderPageBackground() {
        webView.underPageBackgroundColor =
            completedNavigationCount == 0 ? .clear : themeColor
    }

    func recordNavigationFailure(
        _ error: any Error,
        phase: BrowserNavigationFailurePhase,
        navigation: WKNavigation?
    ) {
        guard isCurrentNavigation(navigation) else { return }
        activeNavigation = nil
        let fallbackURL = pendingNavigationURL ?? webView.url ?? url
        pendingNavigationURL = nil
        navigationFailure = BrowserNavigationFailure(
            error: error,
            phase: phase,
            fallbackURL: fallbackURL
        )
        canGoBack = canReturnFromNavigationFailure || webView.canGoBack
    }

    func refreshNavigationState() {
        synchronizeNavigationHistory()
        canGoBack = canReturnFromNavigationFailure || !navigationHistory.backItems.isEmpty || webView.canGoBack
        canGoForward = !navigationHistory.forwardItems.isEmpty || webView.canGoForward
    }

    func clearNavigationFailure(preservingPendingURL: Bool = false) {
        navigationFailure = nil
        if !preservingPendingURL {
            pendingNavigationURL = nil
        }
        refreshNavigationState()
    }

    private func receiveCredentialMessage(_ scriptMessage: WKScriptMessage) {
        credentialSession.receive(scriptMessage, in: webView)
    }

    /// Whether this page's own web view sent `scriptMessage`.
    ///
    /// A popup shares its opener's `WKUserContentController`, so the opener's
    /// user scripts run inside the popup's document and post to the opener's
    /// handlers. Without this check a popup's form would be read against the
    /// opener's top-level origin, and an accepted fill would be evaluated in the
    /// opener's web view against a frame belonging to the popup's.
    private func isOwnScriptMessage(_ scriptMessage: WKScriptMessage) -> Bool {
        scriptMessage.webView === webView
    }

    private func receiveLinkActivationMessage(_ message: WKScriptMessage) {
        guard isOwnScriptMessage(message),
            message.name == MobileLinkActivationContentBridge.messageHandlerName,
            let event = MobileLinkActivationEvent(body: message.body)
        else { return }

        if message.frameInfo.isMainFrame,
            let destinationURL = event.destinationURL,
            let normalizedSourceRect = event.normalizedSourceRect
        {
            downloadSourceStore.record(
                BrowserDownloadSourceCapture(
                    destinationURL: destinationURL,
                    normalizedSourceRect: normalizedSourceRect,
                    normalizedTouchPoint:
                        event.normalizedTouchPoint
                        ?? CGPoint(
                            x: normalizedSourceRect.midX,
                            y: normalizedSourceRect.midY
                        )
                )
            )
        }
        let sourcePresentation =
            message.frameInfo.isMainFrame
            ? sourcePresentation(for: event)
            : nil
        if let destinationURL = event.destinationURL,
            let sourcePresentation
        {
            linkActivationSourceStore.record(
                destinationURL: destinationURL,
                sourcePresentation: sourcePresentation
            )
        }
    }

    func sourcePresentation(
        for event: MobileLinkActivationEvent
    ) -> BrowserPeekSourcePresentation? {
        guard let normalizedSourceRect = event.normalizedSourceRect else { return nil }

        let rectInWebView = CGRect(
            x: normalizedSourceRect.minX * webView.bounds.width,
            y: normalizedSourceRect.minY * webView.bounds.height,
            width: normalizedSourceRect.width * webView.bounds.width,
            height: normalizedSourceRect.height * webView.bounds.height
        )
        let normalizedTouchPoint =
            event.normalizedTouchPoint
            ?? CGPoint(
                x: normalizedSourceRect.midX,
                y: normalizedSourceRect.midY
            )
        let touchPointInWebView = CGPoint(
            x: normalizedTouchPoint.x * webView.bounds.width,
            y: normalizedTouchPoint.y * webView.bounds.height
        )
        guard let window = webView.window,
            window.bounds.width > 0,
            window.bounds.height > 0
        else {
            return BrowserPeekSourcePresentation(
                normalizedMinX: normalizedSourceRect.minX,
                normalizedMinY: normalizedSourceRect.minY,
                normalizedWidth: normalizedSourceRect.width,
                normalizedHeight: normalizedSourceRect.height,
                normalizedTouchX: normalizedTouchPoint.x,
                normalizedTouchY: normalizedTouchPoint.y,
                label: event.label
            )
        }
        let rectInWindow = webView.convert(rectInWebView, to: window)
        let touchPointInWindow = webView.convert(touchPointInWebView, to: window)
        return BrowserPeekSourcePresentation(
            normalizedMinX: rectInWindow.minX / window.bounds.width,
            normalizedMinY: rectInWindow.minY / window.bounds.height,
            normalizedWidth: rectInWindow.width / window.bounds.width,
            normalizedHeight: rectInWindow.height / window.bounds.height,
            normalizedTouchX: touchPointInWindow.x / window.bounds.width,
            normalizedTouchY: touchPointInWindow.y / window.bounds.height,
            label: event.label
        )
    }
}

#if CREST_PHYSICAL_VALIDATION
#endif
