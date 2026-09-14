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
final class MobileBrowserPage: NSObject, BrowserMediaSessionCommandEndpoint {
    var opensModifiedLinksInForeground = false
    private(set) var tabID: TabID
    let spaceID: SpaceID
    let profileID: UUID
    let webView: WKWebView

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
    private(set) var showsProcessFailure = false
    var isFindPresented: Bool { findSession.isPresented }
    var findQuery: String { findSession.query }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    var findFocusRequest: Int { findSession.focusRequest }
    private(set) var pageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel
    let translation = BrowserPageTranslation()
    var readerModeState: BrowserReaderModeState { readerModeSession.state }
    private(set) var isContentBlockingActive = false
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
    @ObservationIgnored lazy var mediaCaptureSession = BrowserMediaCaptureSession(
        webView: webView, permissionCenter: permissionCenter, spaceID: spaceID
    )
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let popupCoordinator: BrowserPopupCoordinator
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored private var appInitiatedURL: URL?
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
    @ObservationIgnored private let credentialSession: BrowserWebKitCredentialSession
    var credentialState: BrowserCredentialPageState<BrowserWebKitCredentialSession.FillTarget> {
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
    @ObservationIgnored private var appliedContentRuleLists: [WKContentRuleList]

    /// False when this page shares the opener's `WKUserContentController`, which
    /// every popup does. Installing the same script message handler twice on it
    /// throws, and removing one would strip it from the opener.
    @ObservationIgnored private let ownsUserContentController: Bool
    @ObservationIgnored private var defaultPageZoom: CGFloat
    @ObservationIgnored private var hasTemporaryPageZoomOverride = false

    var displayURL: URL? {
        navigationFailure?.failingURL ?? pendingNavigationURL ?? url
    }

    var canReturnFromNavigationFailure: Bool {
        guard let navigationFailure else { return false }
        if navigationFailure.phase == .provisional, webView.url != nil {
            return true
        }
        return webView.canGoBack
    }

    init(
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
        appliedContentRuleLists = contentRuleLists
        if let contentRuleList,
            !appliedContentRuleLists.contains(where: { $0 === contentRuleList })
        {
            appliedContentRuleLists.append(contentRuleList)
        }
        isContentBlockingActive = !appliedContentRuleLists.isEmpty
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
        credentialSession = BrowserWebKitCredentialSession(
            spaceID: space.id,
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
                contentRuleLists: appliedContentRuleLists,
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
            prompt: { origin, topLevelURL, requestedSpaceName in
                await MobileBrowserDialogPresenter.presentGeolocationPermission(
                    origin: origin,
                    topLevelURL: topLevelURL,
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
        webView.load(request)
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
        guard webView.backForwardList.currentItem != nil else { return nil }
        return webView.interactionState as? Data
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
        webView.interactionState = state
        guard webView.backForwardList.currentItem != nil else {
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
            tab.iconMode == .automatic
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

    func prepareForSpaceDeletion() {
        faviconSession.stop()
        mediaCaptureSession.reset()
        sitePermissionRequests.setPresentationAvailable(false)
        translation.reset()
        readerModeSession.invalidate()
        mediaSessionCoordinator?.prepareForRemoval()
        downloadCenter.resetAutomaticDownloadSequence(in: webView)
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

    func goBack() {
        if navigationFailure != nil {
            returnFromNavigationFailure()
            return
        }
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    var backHistory: [BrowserNavigationHistoryItem] {
        webView.backForwardList.backList.reversed().enumerated().map { index, item in
            BrowserNavigationHistoryItem(
                depth: index + 1,
                title: Self.navigationTitle(for: item),
                url: item.url
            )
        }
    }

    var forwardHistory: [BrowserNavigationHistoryItem] {
        webView.backForwardList.forwardList.enumerated().map { index, item in
            BrowserNavigationHistoryItem(
                depth: index + 1,
                title: Self.navigationTitle(for: item),
                url: item.url
            )
        }
    }

    func goBack(toDepth depth: Int) {
        let items = webView.backForwardList.backList
        let index = items.count - depth
        guard items.indices.contains(index) else { return }
        clearNavigationFailure()
        webView.go(to: items[index])
    }

    func goForward(toDepth depth: Int) {
        let items = webView.backForwardList.forwardList
        let index = depth - 1
        guard items.indices.contains(index) else { return }
        clearNavigationFailure()
        webView.go(to: items[index])
    }

    func reloadOrStop() {
        performReload(.standard)
    }

    func reload() {
        webView.reload()
    }

    func clearSiteDataAndReload() async {
        guard let targetURL = displayURL ?? webView.url else { return }
        await BrowserWebsiteDataStore.clearSiteData(
            for: targetURL,
            in: webView.configuration.websiteDataStore
        )
        if webView.url == nil {
            load(targetURL)
        } else {
            webView.reloadFromOrigin()
        }
    }

    func stopLoading() {
        webView.stopLoading()
    }

    func performReload(_ mode: BrowserPageReloadMode) {
        switch BrowserPageReloadPolicy.action(isLoading: isLoading, mode: mode) {
        case .stop:
            webView.stopLoading()
        case .reload:
            webView.reload()
        case .reloadFromOrigin:
            webView.reloadFromOrigin()
        }
    }

    func togglePreferredContentMode() {
        isRequestingDesktopSite.toggle()
        webView.configuration.defaultWebpagePreferences.preferredContentMode =
            isRequestingDesktopSite ? .desktop : .recommended
        guard url != nil else { return }
        webView.reloadFromOrigin()
    }

    /// Swaps the content rule lists this page loads with.
    ///
    /// WebKit takes the new set on the page's next navigation, so by default the
    /// document on screen is left exactly as the person left it — a filter-list
    /// update can never discard a half-filled form. `activation` decides whether
    /// this page is also reloaded to surface the change at once, which only the
    /// page the user just changed protection for asks for.
    func applyContentBlocking(
        policy: BrowserContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        let desiredRuleLists = policy == .balanced ? balancedRuleLists : []
        guard !Self.identical(appliedContentRuleLists, desiredRuleLists) else { return }

        let userContentController = webView.configuration.userContentController
        // Exactly what this page installed, never `removeAllContentRuleLists()`,
        // which would also strip a list another owner put on this controller.
        for ruleList in appliedContentRuleLists {
            userContentController.remove(ruleList)
        }
        for ruleList in desiredRuleLists {
            userContentController.add(ruleList)
        }
        appliedContentRuleLists = desiredRuleLists
        isContentBlockingActive = !desiredRuleLists.isEmpty
        guard activation == .immediately, url != nil else { return }
        webView.reload()
    }

    func applyContentBlocking(
        policy: BrowserContentBlockingPolicy,
        balancedRuleList: WKContentRuleList?,
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        applyContentBlocking(
            policy: policy,
            balancedRuleLists: balancedRuleList.map { [$0] } ?? [],
            activation: activation
        )
    }

    private static func identical(
        _ lhs: [WKContentRuleList],
        _ rhs: [WKContentRuleList]
    ) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0 === $1 }
    }

    func retryAfterProcessFailure() {
        processRecovery.reset()
        showsProcessFailure = false
        webView.reload()
    }

    func retryAfterNavigationFailure() {
        guard
            let url = navigationFailure?.failingURL
                ?? pendingNavigationURL
                ?? self.url
        else { return }
        load(url)
    }

    var canProceedAfterCertificateFailure: Bool {
        navigationFailure?.kind == .secureConnectionFailed
            && pendingServerTrustIdentity != nil
    }

    func proceedAfterCertificateFailure() {
        guard canProceedAfterCertificateFailure,
            let identity = pendingServerTrustIdentity
        else { return }
        serverTrustOverrides.approve(identity, for: profileID)
        retryAfterNavigationFailure()
    }

    func returnFromNavigationFailure() {
        guard let navigationFailure else { return }
        let shouldNavigateBack =
            navigationFailure.phase == .committed
            && webView.canGoBack
        clearNavigationFailure()
        if shouldNavigateBack {
            webView.goBack()
        }
    }

    func presentFind() {
        findSession.present(hasLoadedPage: url != nil)
    }

    func dismissFind() {
        findSession.dismiss(using: webView)
    }

    func find(_ query: String, direction: BrowserFindDirection = .forward) {
        findSession.find(query, direction: direction, using: webView)
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

    private static func navigationTitle(for item: WKBackForwardListItem) -> String {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return item.url.host() ?? item.url.absoluteString
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
                    }
                    self?.credentialState.didChangeTopLevelURL(to: webView.url ?? self?.url)
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.recordObservedTitle(webView.title) }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.estimatedProgress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.isLoading = webView.isLoading
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
                Task { @MainActor in self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.canGoForward = webView.canGoForward }
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
        completedNavigationCount &+= 1
        updateUnderPageBackground()
        refreshFavicon()
    }

    private func recordObservedTitle(_ observedTitle: String?) {
        guard title != observedTitle else { return }
        title = observedTitle
        mediaSessionCoordinator?.ownerTitleDidChange()
    }

    private func refreshFavicon() {
        guard navigationContext?.iconMode == .automatic,
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
        webView.pageZoom = zoom
        return true
    }

    func prepareForNavigation(to url: URL?) {
        mediaCaptureSession.reset()
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

    func receiveMediaSessionMessage(_ message: WKScriptMessage) {
        guard message.webView === webView else {
            host?.routeMediaSessionMessage(message)
            return
        }
        mediaSessionCoordinator?.receive(message)
    }

    func performMediaSessionAction(
        _ action: BrowserMediaSessionAction,
        documentIdentifier: String
    ) {
        mediaSessionCoordinator?.perform(
            action,
            documentIdentifier: documentIdentifier
        )
    }

    func setMediaSessionMuted(
        _ muted: Bool,
        documentIdentifier: String
    ) {
        mediaSessionCoordinator?.setMuted(
            muted,
            documentIdentifier: documentIdentifier
        )
    }

    func synchronizePopupPermission(for url: URL? = nil) {
        let origin = (url ?? displayURL ?? webView.url)
            .flatMap(BrowserSiteOrigin.init(url:))
        let decision =
            origin.map {
                permissionCenter.decision(for: .popups, origin: $0, in: spaceID)
            } ?? .ask
        let allowsAutomaticPopups =
            BrowserAutomaticPopupPolicy.allowsAutomaticPopups(decision: decision)
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically =
            allowsAutomaticPopups
        recordPopupPermissionSynchronized(
            allowsAutomaticPopups: allowsAutomaticPopups,
            origin: origin
        )
    }

    /// True when Crest, not web content, asked for this navigation. Two signals
    /// answer that: the exact URL Crest last passed to `load(_:)`, which web
    /// content never reaches, and a source frame that is not a web document —
    /// WebKit reports an empty origin for a load the app started against a web
    /// view with no page yet, and a `file:` origin for a local document's own
    /// links. Only such a navigation may reach a `file:` URL.
    func isAppInitiated(_ navigationAction: WKNavigationAction) -> Bool {
        if let appInitiatedURL, navigationAction.request.url == appInitiatedURL {
            return true
        }
        if let sourceOriginProvider = navigationAction as? any BrowserNavigationActionSourceOriginProviding {
            guard let origin = sourceOriginProvider.browserSourceOrigin else {
                return false
            }
            if origin.scheme.isEmpty, origin.host.isEmpty {
                return true
            }
            return origin.scheme == "file"
        }
        let origin = navigationAction.sourceFrame.securityOrigin
        let scheme = origin.protocol.lowercased()
        if scheme.isEmpty, origin.host.isEmpty {
            return true
        }
        return scheme == "file"
    }

    /// Forgets the URL Crest asked this page to load, once WebKit has begun the
    /// navigation that honored it.
    ///
    /// The marker is a one-shot authorization. Leaving it in place would let web
    /// content replay the exact URL Crest once loaded — the one way past the gate
    /// that keeps `file:` destinations app-initiated.
    func consumeAppInitiatedURL() {
        appInitiatedURL = nil
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

    func clearNavigationFailure(preservingPendingURL: Bool = false) {
        navigationFailure = nil
        if !preservingPendingURL {
            pendingNavigationURL = nil
        }
        canGoBack = webView.canGoBack
    }

    func isCurrentNavigation(_ navigation: WKNavigation?) -> Bool {
        // WebKit can deliver a callback late, after its navigation finished or
        // was replaced. An identified navigation is only current while it is
        // still the active one, so a stale failure cannot paint an error over a
        // page that already loaded. Callbacks that identify no navigation stay
        // accepted because WebKit reports unattributed loads that way.
        guard let navigation else { return true }
        return activeNavigation === navigation
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
