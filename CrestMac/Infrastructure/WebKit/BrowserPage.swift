import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

@Observable
@MainActor
final class BrowserPage: NSObject {
    @ObservationIgnored private static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

    @ObservationIgnored let webView: WKWebView

    private(set) var url: URL?
    private(set) var title = ""
    private(set) var estimatedProgress = 0.0
    private(set) var isLoading = false
    private(set) var hasOnlySecureContent = false
    private(set) var faviconData: Data?
    private(set) var themeColor: NSColor?
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    var processTerminationCount = 0
    var committedNavigationCount = 0
    var completedNavigationCount = 0
    private(set) var navigationFailure: BrowserNavigationFailure?
    var blockedPopupState = BrowserBlockedPopupPageState()
    var pendingServerTrustIdentity: BrowserServerTrustIdentity?
    var pendingNavigationURL: URL?
    var webContentFailureMessage: String?
    var isFindPresented: Bool { findSession.isPresented }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    var findFocusRequest: Int { findSession.focusRequest }
    private(set) var pageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel
    var readerModeState = BrowserReaderModeState.unavailable
    private(set) var isContentBlockingActive = false
    private(set) var developerPanel: BrowserDeveloperPanel?
    private(set) var isRegionCapturePresented = false
    private(set) var developerCaptureFeedback: String?
    private(set) var developerCaptureFeedbackRevision = 0
    private(set) var isCredentialAccessEnabled: Bool
    var credentialFillRequest: BrowserCredentialFillRequest? { credentialState.fillRequest }
    var credentialSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.saveCandidate }
    private(set) var chromeWebStoreInstallItem: BrowserChromeWebStoreItem?
    private(set) var chromeWebStoreCandidate: BrowserChromeWebStoreCandidate?
    private(set) var isPreparingChromeWebStoreExtension = false
    private(set) var isInstallingChromeWebStoreExtension = false
    private(set) var chromeWebStoreInstallErrorDescription: String?
    private(set) var installedChromeWebStoreExtensionName: String?
    private(set) var installedChromeWebStoreCompatibilityIssues: [String] = []
    /// Owns the whole addons.mozilla.org review-and-install flow, so the page
    /// carries one reference instead of another parallel set of phase flags.
    let mozillaAddonsInstall: BrowserMozillaAddonsInstallSession

    /// The pool that owns this page. Weak because the pool owns the page.
    @ObservationIgnored weak var host: (any BrowserPageHosting)?

    /// True when web content opened this page through `window.open()`. It gates
    /// `window.close()`, which may only close what script itself opened.
    @ObservationIgnored private(set) var wasOpenedAsPopup = false

    /// True from adoption until WebKit starts the popup's own navigation. WebKit
    /// drives an adopted popup, so nothing else may load it in that window —
    /// loading it here is what breaks `window.opener` and `document.write`.
    @ObservationIgnored var isAwaitingPopupNavigation = false

    /// False when this page shares the opener's `WKUserContentController`, which
    /// every popup does: WebKit copies the opener's configuration and the copy
    /// keeps the same controller. Installing the same script message handler
    /// twice on it throws, and removing one would strip it from the opener.
    @ObservationIgnored private let ownsUserContentController: Bool
    @ObservationIgnored private let supportsCredentialAccess: Bool
    @ObservationIgnored private var defaultPageZoom: CGFloat
    @ObservationIgnored private var hasTemporaryPageZoomOverride = false

    @ObservationIgnored let dialogPresenter: BrowserDialogPresenter
    @ObservationIgnored let downloadCenter: BrowserDownloadCenter
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let hostedNotificationCenter: (any BrowserHostedWebNotificationCentering)?
    @ObservationIgnored let recoverNotificationSystemAuthorization: @MainActor () async -> Void
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let spaceID: SpaceID
    @ObservationIgnored let profileID: UUID
    @ObservationIgnored let spaceName: String
    /// The extension origin whose context supplied this page's WebKit
    /// configuration. Nil identifies an ordinary browsing page.
    @ObservationIgnored let extensionBaseURL: URL?
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let popupCoordinator: BrowserPopupCoordinator
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored private var appInitiatedURL: URL?
    @ObservationIgnored let openModifiedLink: (URL, SpaceID, Bool) -> Void
    @ObservationIgnored let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored var navigationContext: BrowserPageNavigationContext?
    @ObservationIgnored var activeNavigation: WKNavigation?
    @ObservationIgnored private var observations: Set<AnyCancellable> = []
    @ObservationIgnored var processRecovery = BrowserProcessRecovery()
    @ObservationIgnored private let findSession = BrowserFindSession()
    @ObservationIgnored var readerModeGeneration = 0
    @ObservationIgnored var faviconGeneration = 0
    @ObservationIgnored var sharingPicker: NSSharingServicePicker?
    @ObservationIgnored private var printOperation: NSPrintOperation?
    @ObservationIgnored private var credentialMessageProxy: BrowserCredentialScriptMessageProxy?
    @ObservationIgnored private var linkContextMessageProxy: BrowserLinkContextScriptMessageProxy?
    /// The link the pending web-content context menu is over. Read and cleared
    /// by this page's `BrowserDesktopWebViewMenuHost` conformance.
    @ObservationIgnored var linkContextCapture = BrowserLinkContextCapturePolicy()
    @ObservationIgnored let splitLinkHost: BrowserSplitLinkHost
    @ObservationIgnored private var chromeWebStoreMessageProxy: BrowserChromeWebStoreScriptMessageProxy?
    @ObservationIgnored private var userActivityMessageProxy: BrowserUserActivityScriptMessageProxy?
    @ObservationIgnored private var geolocationMessageProxy: BrowserGeolocationScriptMessageProxy?
    @ObservationIgnored private var blockedPopupMessageProxy: BrowserBlockedPopupScriptMessageProxy?
    @ObservationIgnored var geolocationCoordinator: BrowserGeolocationCoordinator?
    @ObservationIgnored private var hostedNotificationMessageProxy: BrowserHostedWebNotificationScriptMessageProxy?
    @ObservationIgnored var hostedNotificationIdentifiers: Set<String> = []
    @ObservationIgnored var hostedNotificationDocumentIdentifier = UUID().uuidString
    @ObservationIgnored private var userActivityHandler: (() -> Void)?
    @ObservationIgnored let credentialState: BrowserCredentialPageState<CredentialFillTarget>
    @ObservationIgnored let httpAuthenticationSession: BrowserHTTPAuthenticationSession
    @ObservationIgnored private var appliedContentRuleLists: [WKContentRuleList]
    @ObservationIgnored private let prepareChromeWebStoreExtension:
        @MainActor (BrowserChromeWebStoreItem) async throws
            -> BrowserChromeWebStoreCandidate
    @ObservationIgnored private let installChromeWebStoreExtension:
        @MainActor (BrowserChromeWebStoreCandidate) async throws
            -> BrowserExtensionSummary
    @ObservationIgnored private var chromeWebStoreTask: Task<Void, Never>?

    typealias CredentialFillTarget = (formID: String, frame: WKFrameInfo)

    var displayURL: URL? {
        navigationFailure?.failingURL ?? pendingNavigationURL ?? url
    }

    func matches(
        _ extensionConfiguration: BrowserExtensionPageConfiguration?
    ) -> Bool {
        switch (extensionBaseURL, extensionConfiguration?.baseURL) {
        case (nil, nil):
            true
        case (let currentBaseURL?, let requestedBaseURL?):
            currentBaseURL.scheme?.caseInsensitiveCompare(
                requestedBaseURL.scheme ?? ""
            ) == .orderedSame
                && currentBaseURL.host?.caseInsensitiveCompare(
                    requestedBaseURL.host ?? ""
                ) == .orderedSame
                && currentBaseURL.port == requestedBaseURL.port
        default:
            false
        }
    }

    var isDeveloperModeEnabled: Bool {
        BrowserDeveloperModePolicy.isAutomatic(for: displayURL)
    }

    var canReturnFromNavigationFailure: Bool {
        guard let navigationFailure else { return false }
        if navigationFailure.phase == .provisional, webView.url != nil {
            return true
        }
        return webView.canGoBack
    }

    init(
        configuration: WKWebViewConfiguration,
        dialogPresenter: BrowserDialogPresenter,
        downloadCenter: BrowserDownloadCenter,
        permissionCenter: BrowserSitePermissionCenter,
        geolocationService: any BrowserGeolocationServicing =
            BrowserGeolocationSystemService(),
        recoverGeolocationSystemAuthorization:
            BrowserGeolocationCoordinator.RecoverSystemAuthorization? = nil,
        hostedNotificationCenter:
            (any BrowserHostedWebNotificationCentering)? = nil,
        recoverNotificationSystemAuthorization:
            (@MainActor () async -> Void)? = nil,
        serverTrustOverrides: BrowserServerTrustOverrideStore = BrowserServerTrustOverrideStore(),
        spaceID: SpaceID,
        profileID: UUID,
        spaceName: String,
        extensionBaseURL: URL? = nil,
        contentRuleList: WKContentRuleList? = nil,
        contentRuleLists: [WKContentRuleList] = [],
        ownsUserContentController: Bool = true,
        allowsCredentialAccess: Bool = true,
        isCredentialAccessEnabled: Bool = true,
        defaultPageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel,
        allowsChromeWebStoreExtensions: Bool = false,
        prepareChromeWebStoreExtension:
            @escaping @MainActor (BrowserChromeWebStoreItem) async throws
            -> BrowserChromeWebStoreCandidate = { _ in
                throw BrowserExtensionControllerPoolError
                    .unsupportedInstallationSource
            },
        installChromeWebStoreExtension:
            @escaping @MainActor (BrowserChromeWebStoreCandidate) async throws
            -> BrowserExtensionSummary = { _ in
                throw BrowserExtensionControllerPoolError
                    .unsupportedInstallationSource
            },
        allowsMozillaAddonsExtensions: Bool = false,
        prepareMozillaAddonsExtension:
            @escaping BrowserMozillaAddonsInstallSession.Prepare = { _ in
                throw BrowserExtensionControllerPoolError
                    .unsupportedInstallationSource
            },
        installMozillaAddonsExtension:
            @escaping BrowserMozillaAddonsInstallSession.Install = { _ in
                throw BrowserExtensionControllerPoolError
                    .unsupportedInstallationSource
            },
        loadHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.LoadCredential = { _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.SaveCredential = { _ in },
        openNewTab: @escaping (URL) -> Void,
        openModifiedLink: @escaping (URL, SpaceID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        opensExternalURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        let pageInterval = Self.lifecycleSignposter.beginInterval("Initialize Browser Page")
        defer {
            Self.lifecycleSignposter.endInterval("Initialize Browser Page", pageInterval)
        }

        self.dialogPresenter = dialogPresenter
        self.downloadCenter = downloadCenter
        self.permissionCenter = permissionCenter
        self.hostedNotificationCenter = hostedNotificationCenter
        self.recoverNotificationSystemAuthorization =
            recoverNotificationSystemAuthorization
            ?? {
                await dialogPresenter
                    .recoverNotificationSystemAuthorization()
            }
        self.serverTrustOverrides = serverTrustOverrides
        self.spaceID = spaceID
        self.profileID = profileID
        self.spaceName = spaceName
        self.extensionBaseURL = extensionBaseURL
        self.ownsUserContentController = ownsUserContentController
        supportsCredentialAccess = allowsCredentialAccess
        self.isCredentialAccessEnabled =
            allowsCredentialAccess
            && isCredentialAccessEnabled
        let normalizedDefaultPageZoom = BrowserPageZoomPolicy.normalizedDefault(
            defaultPageZoom
        )
        self.defaultPageZoom = normalizedDefaultPageZoom
        pageZoom = normalizedDefaultPageZoom
        self.prepareChromeWebStoreExtension =
            prepareChromeWebStoreExtension
        self.installChromeWebStoreExtension =
            installChromeWebStoreExtension
        mozillaAddonsInstall = BrowserMozillaAddonsInstallSession(
            spaceID: spaceID,
            spaceName: spaceName,
            prepare: prepareMozillaAddonsExtension,
            install: installMozillaAddonsExtension
        )
        appliedContentRuleLists = contentRuleLists
        if let contentRuleList,
            !appliedContentRuleLists.contains(where: { $0 === contentRuleList })
        {
            appliedContentRuleLists.append(contentRuleList)
        }
        isContentBlockingActive = !appliedContentRuleLists.isEmpty
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.splitLinkHost = splitLinkHost
        credentialState = BrowserCredentialPageState(spaceID: spaceID)
        httpAuthenticationSession = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: allowsCredentialAccess
                && isCredentialAccessEnabled,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential
        )
        navigationDecider = BrowserNavigationDecider()
        // Built before the popup coordinator so a popup whose destination belongs
        // to another application can be routed into the same consent path an
        // ordinary external-scheme navigation takes.
        let externalSchemeCoordinator = BrowserExternalSchemeCoordinator(
            spaceID: spaceID,
            spaceName: spaceName,
            permissionCenter: permissionCenter,
            prompt: { origin, destinationURL, requestedSpaceName in
                await dialogPresenter.presentExternalApplicationPermission(
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
        let webViewInterval = Self.lifecycleSignposter.beginInterval("Initialize WKWebView")
        BrowserWebInspectorAccess.enableDeveloperExtras(
            in: configuration.preferences
        )
        let desktopWebView = BrowserDesktopWebView(
            frame: .zero,
            configuration: configuration
        )
        webView = desktopWebView
        Self.lifecycleSignposter.endInterval("Initialize WKWebView", webViewInterval)
        super.init()

        desktopWebView.menuHost = self
        if !BrowserPageZoomPolicy.levelsMatch(
            normalizedDefaultPageZoom,
            BrowserPageZoomPolicy.defaultLevel
        ) {
            webView.pageZoom = normalizedDefaultPageZoom
        }
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        observeWebViewState()
        if allowsCredentialAccess, ownsUserContentController {
            credentialMessageProxy = BrowserCredentialContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveCredentialMessage(message)
            }
        }
        // Private and isolated launches split exactly like a standard one, and
        // the bridge reports a destination rather than storing anything, so the
        // only gate is the shared-controller one every bridge has: a popup runs
        // its opener's scripts against its opener's handlers.
        if ownsUserContentController {
            linkContextMessageProxy = BrowserLinkContextContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveLinkContextMessage(message)
            }
        }
        if extensionBaseURL == nil {
            if ownsUserContentController {
                blockedPopupMessageProxy = BrowserBlockedPopupContentBridge.install(
                    in: webView.configuration.userContentController
                ) { [weak self] message in
                    self?.receiveBlockedPopupMessage(message)
                }
            }
            geolocationCoordinator = BrowserGeolocationCoordinator(
                webView: webView,
                permissionCenter: permissionCenter,
                service: geolocationService,
                spaceID: spaceID,
                spaceName: spaceName,
                prompt: { origin, topLevelURL, requestedSpaceName in
                    await dialogPresenter.presentGeolocationPermission(
                        origin: origin,
                        topLevelURL: topLevelURL,
                        spaceName: requestedSpaceName
                    )
                },
                recoverSystemAuthorization:
                    recoverGeolocationSystemAuthorization
                    ?? {
                        await dialogPresenter
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
        }
        if let hostedNotificationCenter,
            extensionBaseURL == nil,
            ownsUserContentController
        {
            _ = hostedNotificationCenter
            hostedNotificationMessageProxy =
                BrowserHostedWebNotificationContentBridge.install(
                    in: webView.configuration.userContentController
                ) { [weak self] message in
                    self?.receiveHostedWebNotificationMessage(message)
                }
        }
        if allowsChromeWebStoreExtensions, ownsUserContentController {
            chromeWebStoreMessageProxy =
                BrowserChromeWebStoreContentBridge.install(
                    in: webView.configuration.userContentController
                ) { [weak self] message in
                    self?.receiveChromeWebStoreMessage(message)
                }
        }
        if allowsMozillaAddonsExtensions, ownsUserContentController {
            BrowserMozillaAddonsContentBridge.install(
                in: webView.configuration.userContentController
            )
            mozillaAddonsInstall.reportInstalled = { [weak self] slug in
                await self?.markMozillaAddonInstalled(slug)
            }
        }
    }

    /// Records that web content opened this page and that WebKit still owes it a
    /// navigation. Only a page pool adopting a popup calls this.
    func markOpenedAsPopup() {
        wasOpenedAsPopup = true
        isAwaitingPopupNavigation = true
    }

    func load(_ url: URL) {
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
        appInitiatedURL = url
        prepareForNavigation(to: url)
        webView.interactionState = state
        guard webView.backForwardList.currentItem != nil else {
            pendingNavigationURL = nil
            return false
        }
        return true
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
            faviconGeneration += 1
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
        // which would also strip a list an extension put on this controller.
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

    func stopLoading() {
        webView.stopLoading()
    }

    func prepareForSpaceDeletion() {
        chromeWebStoreTask?.cancel()
        chromeWebStoreTask = nil
        mozillaAddonsInstall.cancel()
        downloadCenter.resetAutomaticDownloadSequence(in: webView)
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        (webView as? BrowserDesktopWebView)?.menuHost = nil
        linkContextCapture.clear()
        observations.removeAll()
        removeGeolocationRequests()
        removeHostedWebNotifications()
        guard ownsUserContentController else {
            // A popup shares its opener's content controller. Removing handlers
            // here would silence them for the opener too.
            credentialMessageProxy = nil
            linkContextMessageProxy = nil
            chromeWebStoreMessageProxy = nil
            userActivityMessageProxy = nil
            geolocationMessageProxy = nil
            blockedPopupMessageProxy = nil
            geolocationCoordinator = nil
            hostedNotificationMessageProxy = nil
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
        if linkContextMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserLinkContextContentBridge.messageHandlerName,
                    contentWorld: BrowserLinkContextContentBridge.contentWorld
                )
        }
        linkContextMessageProxy = nil
        if chromeWebStoreMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserChromeWebStoreContentBridge
                        .messageHandlerName,
                    contentWorld: BrowserChromeWebStoreContentBridge
                        .contentWorld
                )
        }
        chromeWebStoreMessageProxy = nil
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
        geolocationCoordinator = nil
        if hostedNotificationMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserHostedWebNotificationContentBridge
                        .messageHandlerName,
                    contentWorld: BrowserHostedWebNotificationContentBridge
                        .contentWorld
                )
        }
        hostedNotificationMessageProxy = nil
        userActivityHandler = nil
    }

    var isChromeWebStoreInstallPresented: Bool {
        chromeWebStoreInstallItem != nil
    }

    var chromeWebStoreInstallSpaceName: String { spaceName }

    func dismissChromeWebStoreInstall() {
        guard !isInstallingChromeWebStoreExtension else { return }
        chromeWebStoreTask?.cancel()
        chromeWebStoreTask = nil
        chromeWebStoreInstallItem = nil
        chromeWebStoreCandidate = nil
        installedChromeWebStoreCompatibilityIssues = []
        isPreparingChromeWebStoreExtension = false
        chromeWebStoreInstallErrorDescription = nil
        installedChromeWebStoreExtensionName = nil
    }

    func installPreparedChromeWebStoreExtension() {
        guard let candidate = chromeWebStoreCandidate,
            !isInstallingChromeWebStoreExtension
        else {
            return
        }
        chromeWebStoreInstallErrorDescription = nil
        isInstallingChromeWebStoreExtension = true
        chromeWebStoreTask?.cancel()
        chromeWebStoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let summary = try await installChromeWebStoreExtension(
                    candidate
                )
                guard !Task.isCancelled else { return }
                isInstallingChromeWebStoreExtension = false
                installedChromeWebStoreExtensionName = summary.displayName
                installedChromeWebStoreCompatibilityIssues = candidate
                    .compatibility.issues.map(\.message)
                chromeWebStoreCandidate = nil
                await markChromeWebStoreExtensionInstalled(candidate.id)
            } catch is CancellationError {
                isInstallingChromeWebStoreExtension = false
            } catch {
                isInstallingChromeWebStoreExtension = false
                chromeWebStoreInstallErrorDescription =
                    error.localizedDescription
            }
        }
    }

    func retryChromeWebStorePreparation() {
        guard let item = chromeWebStoreInstallItem,
            !isInstallingChromeWebStoreExtension
        else {
            return
        }
        beginChromeWebStoreInstall(for: item)
    }

    func retryAfterProcessFailure() {
        processRecovery.reset()
        webContentFailureMessage = nil
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

    @discardableResult
    func showWebInspector() -> Bool {
        BrowserWebInspectorAccess.show(
            inspectorOwner: webView,
            isInspectable: webView.isInspectable
        )
    }

    func toggleDeveloperPanel(_ panel: BrowserDeveloperPanel) {
        let result = BrowserWebInspectorAccess.toggle(
            panel,
            currentPanel: developerPanel,
            inspectorOwner: webView,
            isInspectable: webView.isInspectable
        )
        switch result {
        case .opened(let openedPanel):
            developerPanel = openedPanel
        case .closed:
            developerPanel = nil
        case .unavailable:
            NSSound.beep()
        }
    }

    func beginRegionCapture() {
        guard url != nil else { return }
        isRegionCapturePresented = true
    }

    func cancelRegionCapture() {
        isRegionCapturePresented = false
    }

    func captureRegion(_ rect: CGRect) {
        guard isRegionCapturePresented else { return }
        isRegionCapturePresented = false
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await webView.takeSnapshot(
                    configuration: Self.snapshotConfiguration(rect: rect)
                )
                guard Self.copyImageToPasteboard(image) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                presentDeveloperCaptureFeedback("Capture Copied")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Capture Page")
            }
        }
    }

    func copyFullPageCapture() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await fullPageSnapshot()
                guard Self.copyImageToPasteboard(image) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                presentDeveloperCaptureFeedback("Full Page Capture Copied")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Capture Full Page")
            }
        }
    }

    func savePortraitCapture() {
        Task { [weak self] in
            guard let self, let window = webView.window else { return }
            do {
                let snapshot = try await fullPageSnapshot(snapshotWidth: 720)
                let portrait = Self.portraitImage(from: snapshot)
                guard let data = Self.pngData(from: portrait) else {
                    throw BrowserDeveloperCaptureError.encodingFailed
                }
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue =
                    BrowserDeveloperCapturePolicy
                    .pngFilename(title: title, url: url)
                panel.title = "Save Portrait Capture"
                panel.prompt = "Save"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
                presentDeveloperCaptureFeedback("Portrait Capture Saved")
            } catch {
                presentDeveloperCaptureFeedback("Couldn’t Save Portrait Capture")
            }
        }
    }

    func dismissDeveloperCaptureFeedback() {
        developerCaptureFeedback = nil
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

    /// Updates this page's global baseline without discarding a temporary zoom
    /// chosen through the page commands. A manually zoomed page rejoins the
    /// baseline when Reset is used, when recreation makes a new page, or when
    /// the newly selected default already equals its temporary value.
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

    func dismissCredentialFillRequest() {
        credentialState.dismissFillRequest()
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        let resolvedValue = supportsCredentialAccess && isEnabled
        guard isCredentialAccessEnabled != resolvedValue else { return }
        isCredentialAccessEnabled = resolvedValue
        httpAuthenticationSession.setCredentialStorageEnabled(resolvedValue)
        if !resolvedValue {
            credentialState.reset()
        }
    }

    func dismissCredentialSaveCandidate() {
        credentialState.dismissSaveCandidate()
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

    @discardableResult
    func copyPageLink() -> Bool {
        guard let url else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(url.absoluteString, forType: .string)
        return true
    }

    func copyDeveloperPageLink() {
        if copyPageLink() {
            presentDeveloperCaptureFeedback("URL Copied")
        }
    }

    @discardableResult
    func copyPageLinkAsMarkdown() -> Bool {
        guard let url else { return false }
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedLabel = label.isEmpty ? (url.host() ?? url.absoluteString) : label
        let escapedLabel =
            resolvedLabel
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("[\(escapedLabel)](\(url.absoluteString))", forType: .string)
        return true
    }

    private func fullPageSnapshot(
        snapshotWidth: CGFloat? = nil
    ) async throws -> NSImage {
        guard url != nil else {
            throw BrowserDeveloperCaptureError.pageUnavailable
        }
        let result = try await webView.evaluateJavaScript(
            """
            (() => {
              const root = document.documentElement;
              const body = document.body;
              return [
                Math.max(root?.scrollWidth ?? 0, body?.scrollWidth ?? 0, innerWidth),
                Math.max(root?.scrollHeight ?? 0, body?.scrollHeight ?? 0, innerHeight)
              ];
            })()
            """
        )
        guard let dimensions = result as? [NSNumber],
            dimensions.count == 2
        else {
            throw BrowserDeveloperCaptureError.dimensionsUnavailable
        }

        let width = min(
            max(CGFloat(dimensions[0].doubleValue), webView.bounds.width),
            6_000
        )
        let height = min(
            max(CGFloat(dimensions[1].doubleValue), webView.bounds.height),
            24_000
        )
        let configuration = Self.snapshotConfiguration(
            rect: CGRect(x: 0, y: 0, width: width, height: height)
        )
        let desiredWidth = snapshotWidth ?? min(width, 1_600)
        configuration.snapshotWidth = NSNumber(value: Double(desiredWidth))
        return try await webView.takeSnapshot(configuration: configuration)
    }

    private static func snapshotConfiguration(
        rect: CGRect
    ) -> WKSnapshotConfiguration {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        configuration.afterScreenUpdates = true
        return configuration
    }

    private static func copyImageToPasteboard(_ image: NSImage) -> Bool {
        guard let data = pngData(from: image) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }

    private static func pngData(from image: NSImage) -> Data? {
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard
            let cgImage = image.cgImage(
                forProposedRect: &proposedRect,
                context: nil,
                hints: nil
            )
        else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }

    private static func portraitImage(from snapshot: NSImage) -> NSImage {
        let horizontalInset: CGFloat = 64
        let verticalInset: CGFloat = 72
        let canvasSize = CGSize(
            width: snapshot.size.width + horizontalInset * 2,
            height: snapshot.size.height + verticalInset * 2
        )
        let imageRect = CGRect(
            x: horizontalInset,
            y: verticalInset,
            width: snapshot.size.width,
            height: snapshot.size.height
        )

        return NSImage(size: canvasSize, flipped: false) { canvasRect in
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.34, alpha: 1),
                NSColor(calibratedRed: 0.48, green: 0.25, blue: 0.52, alpha: 1),
                NSColor(calibratedRed: 0.14, green: 0.54, blue: 0.62, alpha: 1),
            ])
            gradient?.draw(in: canvasRect, angle: -35)

            let context = NSGraphicsContext.current
            context?.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.38)
            shadow.shadowBlurRadius = 30
            shadow.shadowOffset = CGSize(width: 0, height: -14)
            shadow.set()
            NSColor.black.withAlphaComponent(0.18).setFill()
            NSBezierPath(
                roundedRect: imageRect.insetBy(dx: -2, dy: -2),
                xRadius: 14,
                yRadius: 14
            ).fill()
            context?.restoreGraphicsState()

            context?.saveGraphicsState()
            NSBezierPath(
                roundedRect: imageRect,
                xRadius: 12,
                yRadius: 12
            ).addClip()
            snapshot.draw(in: imageRect)
            context?.restoreGraphicsState()
            return true
        }
    }

    private func presentDeveloperCaptureFeedback(_ message: String) {
        developerCaptureFeedback = message
        developerCaptureFeedbackRevision &+= 1
    }

    private static func navigationTitle(for item: WKBackForwardListItem) -> String {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return item.url.host() ?? item.url.absoluteString
    }

    func sharePage() {
        guard let url else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        sharingPicker = picker
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.webView.window != nil, self.sharingPicker === picker else { return }
            let anchor = NSRect(
                x: self.webView.bounds.maxX - 1,
                y: self.webView.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            picker.show(relativeTo: anchor, of: self.webView, preferredEdge: .minY)
        }
    }

    func printPage() {
        guard url != nil, let window = webView.window else { return }
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        let operation = webView.printOperation(with: printInfo)
        operation.jobTitle = title.isEmpty ? url?.host() ?? ProductIdentity.name : title
        printOperation = operation
        operation.runModal(
            for: window,
            delegate: self,
            didRun: #selector(printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil
        )
    }

    func pdfData() async throws -> Data {
        guard url != nil else { throw BrowserPageExportError.pageUnavailable }
        return try await webView.pdf(configuration: WKPDFConfiguration())
    }

    func exportPDF() {
        guard let window = webView.window, url != nil else { return }
        let suggestedFilename = BrowserPageExportPolicy.pdfFilename(title: title, url: url)
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await pdfData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.pdf]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedFilename
                panel.title = "Export Page as PDF"
                panel.prompt = "Export"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
            } catch {
                presentPDFExportError(error, in: window)
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

    func exportWebArchive() {
        guard let window = webView.window, url != nil else { return }
        let suggestedFilename = BrowserPageExportPolicy.webArchiveFilename(
            title: title,
            url: url
        )
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await webArchiveData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.webArchive]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = suggestedFilename
                panel.title = "Save Page as Web Archive"
                panel.prompt = "Save"
                guard await panel.beginSheetModal(for: window) == .OK,
                    let destinationURL = panel.url
                else { return }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destinationURL, options: .atomic)
                }.value
            } catch {
                presentWebArchiveExportError(error, in: window)
            }
        }
    }

    @objc private func printOperationDidRun(
        _ operation: NSPrintOperation,
        success: Bool,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        if printOperation === operation {
            printOperation = nil
        }
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
        guard !BrowserPageZoomPolicy.levelsMatch(zoom, pageZoom) else {
            return false
        }
        pageZoom = zoom
        webView.pageZoom = zoom
        return true
    }

    func prepareForNavigation(to url: URL?) {
        beginBlockedPopupNavigation()
        synchronizePopupPermission(for: url)
        if navigationContext?.iconMode == .automatic {
            let current = webView.url.flatMap(BrowserHistoryURL.normalized) ?? webView.url
            let destination = url.flatMap(BrowserHistoryURL.normalized) ?? url
            if current != destination {
                faviconGeneration &+= 1
            }
        }
        pendingNavigationURL = url
        // A capture describes one document's DOM. A right-click whose menu
        // never opened — a page that cancelled the event to draw its own —
        // must not survive into the next document.
        linkContextCapture.clear()
        clearNavigationFailure(preservingPendingURL: true)
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

    /// Whether `navigationAction` would replace this page's own main frame.
    ///
    /// WebKit reports no target frame at all for a new-window request, because the
    /// frame does not exist yet. Reading a missing frame as this page's main frame
    /// is what turns a `target="_blank"` link into a navigation that replaces the
    /// page the user is on.
    func isTopLevelNavigation(_ navigationAction: WKNavigationAction) -> Bool {
        navigationAction.targetFrame?.isMainFrame == true
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

    private func presentPDFExportError(_ error: Error, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The page couldn’t be exported."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func presentWebArchiveExportError(_ error: Error, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The page couldn’t be saved as a web archive."
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func observeWebViewState() {
        webView.publisher(for: \.url, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.url = value
                self?.credentialState.didChangeTopLevelURL(to: value)
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.title, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.title = value ?? "" }
        }
        .store(in: &observations)
        webView.publisher(for: \.estimatedProgress, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.estimatedProgress = value }
        }
        .store(in: &observations)
        webView.publisher(for: \.isLoading, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.isLoading = value }
        }
        .store(in: &observations)
        webView.publisher(for: \.hasOnlySecureContent, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.hasOnlySecureContent = value }
        }
        .store(in: &observations)
        webView.publisher(for: \.themeColor, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.themeColor = value }
        }
        .store(in: &observations)
        webView.publisher(for: \.canGoBack, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.canGoBack = value }
        }
        .store(in: &observations)
        webView.publisher(for: \.canGoForward, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.canGoForward = value }
        }
        .store(in: &observations)
    }

    func refreshFavicon() {
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
        if data == nil {
            for delay in [Duration.milliseconds(500), .seconds(2)] {
                try? await Task.sleep(for: delay)
                guard generation == faviconGeneration,
                    navigationURL == webView.url
                else { return nil }
                data = await BrowserFaviconCapture.capture(from: webView)
                if data != nil { break }
            }
        }
        guard generation == faviconGeneration, navigationURL == webView.url else { return nil }
        if let data {
            faviconData = data
        }
        return data
    }

    var siteThemeIconAccent: BrowserTabIconAccent? {
        guard let color = themeColor?.usingColorSpace(.sRGB), color.alphaComponent > 0 else {
            return nil
        }
        return BrowserTabIconAccent(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
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

    /// Records the link the person just right-clicked, moments before WebKit
    /// hands AppKit the menu that right-click opens.
    private func receiveLinkContextMessage(_ scriptMessage: WKScriptMessage) {
        guard isOwnScriptMessage(scriptMessage),
            scriptMessage.name
                == BrowserLinkContextContentBridge.messageHandlerName
        else { return }
        linkContextCapture.record(body: scriptMessage.body)
    }

    private func receiveChromeWebStoreMessage(
        _ scriptMessage: WKScriptMessage
    ) {
        guard
            isOwnScriptMessage(scriptMessage),
            scriptMessage.name
                == BrowserChromeWebStoreContentBridge.messageHandlerName,
            scriptMessage.frameInfo.isMainFrame,
            scriptMessage.frameInfo.securityOrigin.protocol == "https",
            scriptMessage.frameInfo.securityOrigin.host
                == "chromewebstore.google.com",
            let body = scriptMessage.body as? [String: Any],
            (body["version"] as? NSNumber)?.intValue == 1,
            let encodedID = body["extensionID"] as? String,
            let messageID = BrowserChromeExtensionID(encodedID),
            let encodedURL = body["url"] as? String,
            let messageURL = URL(string: encodedURL),
            let messageItem = BrowserChromeWebStoreItem(url: messageURL),
            let currentURL = webView.url,
            let currentItem = BrowserChromeWebStoreItem(url: currentURL),
            messageItem.id == messageID,
            currentItem.id == messageID
        else {
            return
        }
        beginChromeWebStoreInstall(for: currentItem)
    }

    func beginChromeWebStoreInstall(
        for item: BrowserChromeWebStoreItem
    ) {
        chromeWebStoreTask?.cancel()
        chromeWebStoreInstallItem = item
        chromeWebStoreCandidate = nil
        installedChromeWebStoreExtensionName = nil
        installedChromeWebStoreCompatibilityIssues = []
        chromeWebStoreInstallErrorDescription = nil
        isInstallingChromeWebStoreExtension = false
        isPreparingChromeWebStoreExtension = true
        chromeWebStoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let candidate = try await prepareChromeWebStoreExtension(item)
                guard !Task.isCancelled,
                    chromeWebStoreInstallItem?.id == candidate.item.id
                else {
                    return
                }
                chromeWebStoreCandidate = candidate
                isPreparingChromeWebStoreExtension = false
            } catch is CancellationError {
                isPreparingChromeWebStoreExtension = false
            } catch {
                isPreparingChromeWebStoreExtension = false
                chromeWebStoreInstallErrorDescription =
                    error.localizedDescription
            }
        }
    }

    private func markChromeWebStoreExtensionInstalled(
        _ extensionID: String
    ) async {
        _ = try? await webView.callAsyncJavaScript(
            "globalThis.__crestChromeWebStoreBridge?.setInstalled(extensionID);",
            arguments: ["extensionID": extensionID],
            in: nil,
            contentWorld: BrowserChromeWebStoreContentBridge.contentWorld
        )
    }

    private func markMozillaAddonInstalled(
        _ slug: BrowserMozillaAddonSlug
    ) async {
        _ = try? await webView.callAsyncJavaScript(
            "globalThis.__crestMozillaAddonsBridge?.setInstalled(slug);",
            arguments: ["slug": slug.rawValue],
            in: nil,
            contentWorld: BrowserMozillaAddonsContentBridge.contentWorld
        )
    }

    private func credentialOrigin(for securityOrigin: WKSecurityOrigin) -> CredentialOrigin? {
        CredentialOrigin(
            securityProtocol: securityOrigin.protocol,
            host: securityOrigin.host,
            port: securityOrigin.port
        )
    }
}
