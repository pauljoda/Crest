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
final class MobileBrowserPage: NSObject {
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
    var pendingServerTrustIdentity: BrowserServerTrustIdentity?
    var pendingNavigationURL: URL?
    private(set) var showsProcessFailure = false
    var isFindPresented: Bool { findSession.isPresented }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    private(set) var pageZoom: CGFloat = 1
    var readerModeState = BrowserReaderModeState.unavailable
    private(set) var isContentBlockingActive = false
    private(set) var isRequestingDesktopSite = false
    private(set) var isCredentialAccessEnabled: Bool
    /// True once iOS reclaimed this page's web-content process while it was off
    /// screen. Selecting the tab again is what brings the page back.
    private(set) var needsWebContentRestore = false
    var credentialFillRequest: BrowserCredentialFillRequest? { credentialState.fillRequest }
    var credentialSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.saveCandidate }
    var hasActiveLinkPeekBridge: Bool { linkPeekMessageProxy != nil }

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let pullToRefreshControl = UIRefreshControl()
    @ObservationIgnored private let openNewTab: (URL) -> Void
    @ObservationIgnored let openModifiedLink: (URL, SpaceID, Bool) -> Void
    @ObservationIgnored let downloadCenter: BrowserDownloadCenter
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let popupCoordinator: BrowserPopupCoordinator
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored private var appInitiatedURL: URL?
    @ObservationIgnored let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored private let stagePeek: ((BrowserPeekRequest) -> Void)?
    @ObservationIgnored private let commitPeek: ((BrowserPeekRequest) -> Void)?
    @ObservationIgnored private let cancelStagedPeek: ((UUID) -> Void)?
    @ObservationIgnored var navigationContext: BrowserPageNavigationContext?
    @ObservationIgnored var activeNavigation: WKNavigation?
    @ObservationIgnored let spaceName: String
    @ObservationIgnored private var processRecovery = BrowserProcessRecovery()
    @ObservationIgnored private let findSession = BrowserFindSession()
    @ObservationIgnored var readerModeGeneration = 0
    @ObservationIgnored var faviconGeneration = 0
    @ObservationIgnored let credentialState: BrowserCredentialPageState<CredentialFillTarget>
    @ObservationIgnored private var credentialMessageProxy: BrowserCredentialScriptMessageProxy?
    @ObservationIgnored private var linkPeekMessageProxy: MobileLinkPeekScriptMessageProxy?
    @ObservationIgnored let linkPeekPressCoordinator = MobileLinkPeekPressCoordinator()
    @ObservationIgnored var linkActivationSourceStore = MobileLinkActivationSourceStore()
    @ObservationIgnored private var userActivityMessageProxy: BrowserUserActivityScriptMessageProxy?
    @ObservationIgnored private var geolocationMessageProxy: BrowserGeolocationScriptMessageProxy?
    @ObservationIgnored var geolocationCoordinator: BrowserGeolocationCoordinator?
    @ObservationIgnored private var userActivityHandler: (() -> Void)?
    @ObservationIgnored let httpAuthenticationSession: BrowserHTTPAuthenticationSession
    @ObservationIgnored private var appliedContentRuleLists: [WKContentRuleList]

    /// False when this page shares the opener's `WKUserContentController`, which
    /// every popup does. Installing the same script message handler twice on it
    /// throws, and removing one would strip it from the opener.
    @ObservationIgnored private let ownsUserContentController: Bool
    /// False for a page that may never touch credentials at all, such as a
    /// private-browsing page. It outranks the Space's own saving preference.
    @ObservationIgnored private let supportsCredentialAccess: Bool

    typealias CredentialFillTarget = (formID: String, frame: WKFrameInfo)

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
        websiteDataStore: WKWebsiteDataStore? = nil,
        adoptedConfiguration: WKWebViewConfiguration? = nil,
        contentRuleList: WKContentRuleList? = nil,
        contentRuleLists: [WKContentRuleList] = [],
        allowsCredentialAccess: Bool = true,
        isCredentialAccessEnabled: Bool = true,
        loadsInitialURL: Bool = true,
        loadHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.LoadCredential = { _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.SaveCredential = { _ in },
        openNewTab: @escaping (URL) -> Void,
        openModifiedLink: @escaping (URL, SpaceID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        stagePeek: ((BrowserPeekRequest) -> Void)? = nil,
        commitPeek: ((BrowserPeekRequest) -> Void)? = nil,
        cancelStagedPeek: ((UUID) -> Void)? = nil,
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
        self.openNewTab = openNewTab
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.stagePeek = stagePeek
        self.commitPeek = commitPeek
        self.cancelStagedPeek = cancelStagedPeek
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
            spaceID: space.id,
            spaceName: space.name,
            permissionCenter: permissionCenter,
            prompt: { origin, destinationURL, requestedSpaceName in
                await MobileBrowserDialogPresenter.presentPopupPermission(
                    origin: origin,
                    destinationURL: destinationURL,
                    spaceName: requestedSpaceName
                )
            },
            openNewTab: openNewTab,
            handOffExternalScheme: { destinationURL, trigger, origin in
                externalSchemeCoordinator.handOff(
                    destinationURL: destinationURL,
                    trigger: trigger,
                    origin: origin
                )
            }
        )
        supportsCredentialAccess = allowsCredentialAccess
        self.isCredentialAccessEnabled =
            allowsCredentialAccess
            && isCredentialAccessEnabled
        credentialState = BrowserCredentialPageState(spaceID: space.id)
        httpAuthenticationSession = BrowserHTTPAuthenticationSession(
            spaceID: space.id,
            allowsCredentialSaving: allowsCredentialAccess
                && isCredentialAccessEnabled,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential
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
            var installedLinkPeekProxy: MobileLinkPeekScriptMessageProxy?
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
                installedLinkPeekProxy = MobileLinkPeekContentBridge.install(
                    in: configuration.userContentController
                )
            }
            linkPeekMessageProxy = installedLinkPeekProxy
        }
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()
        #if DEBUG
            // iOS ships no developer tooling of its own, so an inspectable
            // release web view would be attack surface and nothing else: any
            // trusted Mac could attach Safari's Web Inspector to a session.
            webView.isInspectable = true
        #endif
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = false
        linkPeekMessageProxy?.receive = { [weak self] message in
            self?.receiveLinkPeekPressMessage(message)
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
        self.url = url
        appInitiatedURL = url
        prepareForNavigation(to: url)
        webView.load(URLRequest(url: url))
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
        let shouldRefreshAutomaticIcon =
            tab.iconMode == .automatic
            && !tab.hasCurrentAutomaticFavicon
            && webView.url != nil
            && !webView.isLoading
        if faviconData != tab.displayFaviconData {
            faviconGeneration &+= 1
            faviconData = tab.displayFaviconData
        }
        navigationContext = BrowserPageNavigationContext(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            automaticallyOpensPeek: automaticallyOpensPeek
        )
        if shouldRefreshAutomaticIcon {
            refreshFavicon()
        }
    }

    func prepareForSpaceDeletion() {
        linkPeekPressCoordinator.cancel()
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
            linkPeekMessageProxy = nil
            userActivityMessageProxy = nil
            geolocationMessageProxy = nil
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
        if linkPeekMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: MobileLinkPeekContentBridge.messageHandlerName,
                    contentWorld: MobileLinkPeekContentBridge.contentWorld
                )
        }
        linkPeekMessageProxy?.receive = { _ in }
        linkPeekMessageProxy = nil
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
        setPageZoom(BrowserPageZoomPolicy.increased(from: pageZoom))
    }

    @discardableResult
    func zoomOut() -> Bool {
        setPageZoom(BrowserPageZoomPolicy.decreased(from: pageZoom))
    }

    @discardableResult
    func resetZoom() -> Bool {
        setPageZoom(1)
    }

    func refreshReaderModeAvailability() async {
        guard !readerModeState.isActive else { return }
        readerModeGeneration &+= 1
        let generation = readerModeGeneration
        let navigationURL = webView.url
        guard navigationURL != nil else {
            readerModeState = .unavailable
            return
        }

        readerModeState = .checking
        do {
            let isAvailable = try await BrowserReaderModeController.isAvailable(
                in: webView
            )
            guard generation == readerModeGeneration,
                navigationURL == webView.url
            else { return }
            readerModeState = isAvailable ? .available : .unavailable
        } catch {
            guard generation == readerModeGeneration else { return }
            readerModeState = .unavailable
        }
    }

    func setReaderModeActive(_ isActive: Bool) async throws {
        readerModeGeneration &+= 1
        let generation = readerModeGeneration
        let navigationURL = webView.url
        guard navigationURL != nil else {
            readerModeState = .unavailable
            throw BrowserReaderModeError.articleUnavailable
        }

        if isActive {
            if readerModeState != .available {
                let isAvailable = try await BrowserReaderModeController.isAvailable(
                    in: webView
                )
                guard isAvailable else {
                    readerModeState = .unavailable
                    throw BrowserReaderModeError.articleUnavailable
                }
            }
            readerModeState = .activating
            do {
                try await BrowserReaderModeController.activate(in: webView)
            } catch {
                readerModeState = .unavailable
                throw error
            }
            guard generation == readerModeGeneration,
                navigationURL == webView.url
            else {
                throw BrowserReaderModeError.presentationFailed
            }
            readerModeState = .active
        } else {
            try await BrowserReaderModeController.deactivate(in: webView)
            guard generation == readerModeGeneration,
                navigationURL == webView.url
            else {
                throw BrowserReaderModeError.presentationFailed
            }
            let isAvailable = try await BrowserReaderModeController.isAvailable(
                in: webView
            )
            guard generation == readerModeGeneration,
                navigationURL == webView.url
            else {
                throw BrowserReaderModeError.presentationFailed
            }
            readerModeState = isAvailable ? .available : .unavailable
        }
    }

    func toggleReaderMode() {
        let shouldActivate = !readerModeState.isActive
        Task { [weak self] in
            try? await self?.setReaderModeActive(shouldActivate)
        }
    }

    @discardableResult
    func copyPageLink() -> Bool {
        guard let url else { return false }
        UIPasteboard.general.url = url
        return true
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

    /// Brings this page in line with its Space's "save passwords" preference.
    ///
    /// Turning it off has to reach further than the next prompt: HTTP
    /// authentication stops offering to store what it collects, and any fill or
    /// save request already on screen goes away with the permission that raised it.
    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        let resolvedValue = supportsCredentialAccess && isEnabled
        guard isCredentialAccessEnabled != resolvedValue else { return }
        isCredentialAccessEnabled = resolvedValue
        httpAuthenticationSession.setCredentialStorageEnabled(resolvedValue)
        if !resolvedValue {
            credentialState.reset()
        }
    }

    func fillCredential(_ credential: BrowserCredential, for requestID: UUID) async throws {
        guard isCredentialAccessEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try credentialState.fillContext(for: requestID, credential: credential)
        let result = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fill(formID, username, password) === true;",
            arguments: [
                "formID": context.target.formID,
                "username": credential.descriptor.username,
                "password": credential.password,
            ],
            in: context.target.frame,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
        credentialState.completeFill(username: credential.descriptor.username, requestID: requestID)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID) async throws {
        guard isCredentialAccessEnabled else {
            throw BrowserCredentialFillError.staleOrMismatchedRequest
        }
        let context = try credentialState.generatedPasswordFillContext(for: requestID)
        let result = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fillGenerated(formID, password) === true;",
            arguments: [
                "formID": context.target.formID,
                "password": password,
            ],
            in: context.target.frame,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        guard result as? Bool == true else {
            throw BrowserCredentialFillError.formChanged
        }
        credentialState.completeGeneratedPasswordFill(requestID: requestID)
    }

    private func installObservations() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    if let url = webView.url {
                        self?.url = url
                    }
                    self?.credentialState.didChangeTopLevelURL(to: webView.url ?? self?.url)
                }
            },
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.title = webView.title }
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
                    webView.underPageBackgroundColor = themeColor
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
        title = webView.title
        processRecovery.recordSuccessfulNavigation()
        showsProcessFailure = false
        needsWebContentRestore = false
        completedNavigationCount &+= 1
        refreshFavicon()
    }

    private func refreshFavicon() {
        guard navigationContext?.iconMode == .automatic,
            webView.url != nil
        else { return }
        Task { [weak self] in
            _ = await self?.pullFavicon()
        }
    }

    func pullFavicon() async -> Data? {
        faviconGeneration &+= 1
        let generation = faviconGeneration
        let navigationURL = webView.url
        var data = await BrowserFaviconCapture.capture(from: webView)
        if data == nil, let navigationURL {
            data = await BrowserFaviconFallbackLoader.shared.data(
                for: navigationURL,
                profileID: profileID
            )
        }
        guard generation == faviconGeneration, navigationURL == webView.url else { return nil }
        if let data {
            faviconData = data
        }
        return data
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

    private func setPageZoom(_ zoom: CGFloat) -> Bool {
        guard zoom != pageZoom else { return false }
        pageZoom = zoom
        webView.pageZoom = zoom
        return true
    }

    func prepareForNavigation(to url: URL?) {
        if navigationContext?.iconMode == .automatic {
            let current = webView.url.flatMap(BrowserHistoryURL.normalized) ?? webView.url
            let destination = url.flatMap(BrowserHistoryURL.normalized) ?? url
            if current != destination {
                faviconGeneration &+= 1
            }
        }
        pendingNavigationURL = url
        clearNavigationFailure(preservingPendingURL: true)
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
        guard isCredentialAccessEnabled,
            isOwnScriptMessage(scriptMessage),
            scriptMessage.name == BrowserCredentialContentBridge.messageHandlerName,
            let message = BrowserCredentialFormMessage(body: scriptMessage.body),
            let frameOrigin = credentialOrigin(for: scriptMessage.frameInfo.securityOrigin),
            let topLevelURL = webView.url,
            let topLevelOrigin = CredentialOrigin(url: topLevelURL)
        else {
            return
        }

        credentialState.receive(
            message,
            frameOrigin: frameOrigin,
            topLevelOrigin: topLevelOrigin,
            isMainFrame: scriptMessage.frameInfo.isMainFrame,
            fillTarget: message.formID.map { ($0, scriptMessage.frameInfo) }
        )
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

    private func credentialOrigin(for securityOrigin: WKSecurityOrigin) -> CredentialOrigin? {
        CredentialOrigin(
            securityProtocol: securityOrigin.protocol,
            host: securityOrigin.host,
            port: securityOrigin.port
        )
    }

    private func receiveLinkPeekPressMessage(_ message: WKScriptMessage) {
        guard isOwnScriptMessage(message),
            message.name == MobileLinkPeekContentBridge.messageHandlerName,
            let event = MobileLinkPeekPressEvent(body: message.body)
        else { return }

        switch event.phase {
        case .began:
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
            guard
                let request = BrowserPeekPolicy.longPressRequest(
                    destinationURL: event.destinationURL,
                    context: navigationContext,
                    sourcePresentation: sourcePresentation
                )
            else { return }
            linkPeekPressCoordinator.begin(
                pressID: event.pressID,
                request: request,
                stage: { [weak self] request in
                    guard request.sourcePresentation != nil else { return }
                    self?.stagePeek?(request)
                },
                commit: { [weak self] request in
                    let feedback = UIImpactFeedbackGenerator(style: .soft)
                    feedback.prepare()
                    feedback.impactOccurred(intensity: 0.82)
                    if let commitPeek = self?.commitPeek {
                        commitPeek(request)
                    } else {
                        self?.openPeek(request)
                    }
                },
                cancelStaged: { [weak self] requestID in
                    self?.cancelStagedPeek?(requestID)
                }
            )
        case .ended, .cancelled:
            linkPeekPressCoordinator.end(pressID: event.pressID)
        }
    }

    func sourcePresentation(
        for event: MobileLinkPeekPressEvent
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
