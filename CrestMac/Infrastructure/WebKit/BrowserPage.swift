import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

@Observable
@MainActor
final class BrowserPage: NSObject, BrowserMediaSessionCommandEndpoint, BrowserPagePermissionProviding {
    var opensModifiedLinksInForeground = false
    @ObservationIgnored private static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

    #if CREST_CHROMIUM_HOST
    @ObservationIgnored let pageEngine: ChromiumNativePage
    var chromiumPage: ChromiumNativePage? { pageEngine }
    var webView: WKWebView? { nil }
    #else
    @ObservationIgnored let pageEngine: BrowserWebKitPageEngine
    var webView: WKWebView { pageEngine.webView }
    #endif
    @ObservationIgnored lazy var pictureInPicture = webKitView.map { BrowserPictureInPicturePageController(webView: $0) }
    @ObservationIgnored lazy var linkHover: BrowserLinkHoverController? =
        webKitView.map { BrowserLinkHoverController(webView: $0) }
        ?? BrowserLinkHoverController(contentView: pageEngine.nativeView)
    #if CREST_CHROMIUM_HOST
    @ObservationIgnored lazy var linkDrag: BrowserLinkDragController? = BrowserLinkDragController(
        nativeView: nativeView,
        context: { [weak self] in self?.navigationContext },
        handle: { [weak self] event in self?.handleLinkDrag(event) })
    #else
    @ObservationIgnored lazy var linkDrag = webKitView.map { webView in
        BrowserLinkDragController(
            webView: webView,
            context: { [weak self] in self?.navigationContext },
            handle: { [weak self] event in self?.handleLinkDrag(event) }
        )
    }
    #endif
    @ObservationIgnored lazy var focusRestoration: BrowserWebFocusRestorationController = {
        let controller = BrowserWebFocusRestorationController(webView: nativeView)
        (webView as? BrowserDesktopWebView)?.focusRestoration = controller
        return controller
    }()

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
    private(set) var engineInfoBars: [BrowserEngineInfoBar] = []
    var pendingServerTrustIdentity: BrowserServerTrustIdentity?
    var pendingNavigationURL: URL?
    #if CREST_CHROMIUM_HOST
    var navigationHistory: BrowserPageNavigationHistory {
        get { BrowserPageNavigationHistory() }
        set { }
    }
    #else
    var navigationHistory: BrowserPageNavigationHistory {
        get { pageEngine.history }
        set { pageEngine.history = newValue }
    }
    #endif
    var webContentFailureMessage: String?
    var isFindPresented: Bool { findSession.isPresented }
    var findQuery: String { findSession.query }
    var findMatchState: BrowserFindMatchState { findSession.matchState }
    var findFocusRequest: Int { findSession.focusRequest }
    private(set) var pageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel
    let translation = BrowserPageTranslation()
    var readerModeState: BrowserReaderModeState { readerModeSession?.state ?? .unavailable }
    var isContentBlockingActive: Bool { contentRuleSession.isActive }
    private(set) var developerPanel: BrowserDeveloperPanel?
    private(set) var isRegionCapturePresented = false
    private(set) var developerCaptureFeedback: String?
    private(set) var developerCaptureFeedbackRevision = 0
    var isCredentialAccessEnabled: Bool { credentialSession.isEnabled }
    var credentialFillRequest: BrowserCredentialFillRequest? { credentialState.fillRequest }
    var credentialSaveCandidate: BrowserCredentialSaveCandidate? { credentialState.saveCandidate }
    /// The pool that owns this page. Weak because the pool owns the page.
    @ObservationIgnored weak var host: (any BrowserPageHosting)?
    @ObservationIgnored var windowRouting: BrowserPageWindowRouting?

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
    @ObservationIgnored private var defaultPageZoom: CGFloat
    @ObservationIgnored private var hasTemporaryPageZoomOverride = false
    @ObservationIgnored var viewportFitOwner: UUID?
    @ObservationIgnored var viewportFitGeneration = 0

    @ObservationIgnored let dialogPresenter: BrowserDialogPresenter
    @ObservationIgnored let fileUploadAccess = BrowserFileUploadAccess()
    @ObservationIgnored var downloadCenter: BrowserDownloadCenter
    let sitePermissionRequests = BrowserPagePermissionController()
    @ObservationIgnored lazy var mediaCaptureSession = webKitView.map {
        BrowserMediaCaptureSession(webView: $0, permissionCenter: permissionCenter, spaceID: spaceID)
    }
    @ObservationIgnored let permissionCenter: BrowserSitePermissionCenter
    @ObservationIgnored let hostedNotificationCenter: (any BrowserHostedWebNotificationCentering)?
    @ObservationIgnored let recoverNotificationSystemAuthorization: @MainActor () async -> Void
    @ObservationIgnored let serverTrustOverrides: BrowserServerTrustOverrideStore
    @ObservationIgnored let spaceID: SpaceID
    @ObservationIgnored let profileID: UUID
    @ObservationIgnored let spaceName: String
    @ObservationIgnored let navigationDecider: BrowserNavigationDecider
    @ObservationIgnored let popupCoordinator: BrowserPopupCoordinator
    @ObservationIgnored let externalSchemeCoordinator: BrowserExternalSchemeCoordinator
    /// The URL Crest asked this page to load, as opposed to one web content
    /// asked for. Only an app-initiated load may reach a `file:` URL.
    @ObservationIgnored var appInitiatedURL: URL?
    @ObservationIgnored let openModifiedLink: (URLRequest, SpaceID, Bool) -> Void
    @ObservationIgnored let openPeek: (BrowserPeekRequest) -> Void
    @ObservationIgnored let handleLinkDrag: (BrowserPeekInteractionEvent) -> Void
    @ObservationIgnored var navigationContext: BrowserPageNavigationContext?
    @ObservationIgnored var activeNavigation: WKNavigation?
    @ObservationIgnored private var observations: Set<AnyCancellable> = []
    @ObservationIgnored var processRecovery = BrowserProcessRecovery()
    @ObservationIgnored private let findSession = BrowserFindSession()
    @ObservationIgnored lazy var readerModeSession = webKitView.map {
        BrowserReaderModeSession(document: BrowserWebKitReaderModeDocument(webView: $0, translation: translation))
    }
    @ObservationIgnored lazy var faviconSession = webKitView.map {
        BrowserFaviconSession(
            document: BrowserWebKitFaviconDocument(webView: $0, profileID: profileID),
            policy: .delayedDocumentIcons,
            receive: { [weak self] in self?.faviconData = $0 }
        )
    }
    @ObservationIgnored var sharingPicker: NSSharingServicePicker?
    @ObservationIgnored private var printOperation: NSPrintOperation?
    @ObservationIgnored private var preparingPrint = false
    @ObservationIgnored private var credentialMessageProxy: BrowserCredentialScriptMessageProxy?
    @ObservationIgnored private var linkContextMessageProxy: BrowserLinkContextScriptMessageProxy?
    /// The link the pending web-content context menu is over. Read and cleared
    /// by this page's `BrowserDesktopWebViewMenuHost` conformance.
    @ObservationIgnored var linkContextCapture = BrowserLinkContextCapturePolicy()
    @ObservationIgnored var downloadSourceStore = BrowserDownloadSourceStore()
    @ObservationIgnored var splitLinkHost: BrowserSplitLinkHost
    @ObservationIgnored var linkDestinationHost: BrowserLinkDestinationHost
    @ObservationIgnored private var userActivityMessageProxy: BrowserUserActivityScriptMessageProxy?
    @ObservationIgnored private var geolocationMessageProxy: BrowserGeolocationScriptMessageProxy?
    @ObservationIgnored private var blockedPopupMessageProxy: BrowserBlockedPopupScriptMessageProxy?
    @ObservationIgnored private var mediaSessionMessageProxy: BrowserMediaSessionScriptMessageProxy?
    @ObservationIgnored var mediaSessionCoordinator: BrowserMediaSessionPageCoordinator?
    @ObservationIgnored var geolocationCoordinator: BrowserGeolocationCoordinator?
    @ObservationIgnored private var hostedNotificationMessageProxy: BrowserHostedWebNotificationScriptMessageProxy?
    @ObservationIgnored var hostedNotificationIdentifiers: Set<String> = []
    @ObservationIgnored var hostedNotificationDocumentIdentifier = UUID().uuidString
    @ObservationIgnored private var userActivityHandler: (() -> Void)?
    @ObservationIgnored private let credentialSession: BrowserCredentialSession
    var credentialState: BrowserCredentialPageState<BrowserCredentialSession.FillTarget> {
        credentialSession.state
    }
    @ObservationIgnored let httpAuthenticationSession: BrowserHTTPAuthenticationSession
    @ObservationIgnored private let contentRuleSession: BrowserPageContentRuleSession
    var displayURL: URL? {
        navigationFailure?.failingURL ?? pendingNavigationURL ?? url
    }

    // Session-only presentation state belongs to the live page, including in splits.
    private var developerToolbarVisibilityOverride: Bool?
    var developerViewport: BrowserDeveloperViewport? {
        didSet { pageEngine.setZoom(renderedPageZoom) }
    }

    var renderedPageZoom: CGFloat { developerViewport == nil ? pageZoom : 1 }

    var isDeveloperModeEnabled: Bool {
        developerToolbarVisibilityOverride
            ?? (developerViewport != nil || BrowserDeveloperModePolicy.isAutomatic(for: displayURL))
    }

    func setDeveloperToolbarVisible(_ visible: Bool) {
        developerToolbarVisibilityOverride = visible
        if !visible { developerViewport = nil }
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
        mediaSessionStore: BrowserMediaSessionStore? = nil,
        spaceID: SpaceID,
        profileID: UUID,
        spaceName: String,
        contentRuleList: WKContentRuleList? = nil,
        contentRuleLists: [WKContentRuleList] = [],
        ownsUserContentController: Bool = true,
        allowsCredentialAccess: Bool = true,
        isCredentialAccessEnabled: Bool = true,
        defaultPageZoom: CGFloat = BrowserPageZoomPolicy.defaultLevel,
        loadHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.LoadCredential = { _ in nil },
        saveHTTPAuthenticationCredential:
            @escaping BrowserHTTPAuthenticationSession.SaveCredential = { _ in },
        openNewTab: @escaping (URL) -> Void,
        openModifiedLink: @escaping (URLRequest, SpaceID, Bool) -> Void = { _, _, _ in },
        openPeek: @escaping (BrowserPeekRequest) -> Void = { _ in },
        handleLinkDrag: @escaping (BrowserPeekInteractionEvent) -> Void = { _ in },
        splitLinkHost: BrowserSplitLinkHost = .unavailable,
        linkDestinationHost: BrowserLinkDestinationHost = .unavailable,
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
        self.ownsUserContentController = ownsUserContentController
        let normalizedDefaultPageZoom = BrowserPageZoomPolicy.normalizedDefault(
            defaultPageZoom
        )
        self.defaultPageZoom = normalizedDefaultPageZoom
        pageZoom = normalizedDefaultPageZoom
        contentRuleSession = BrowserPageContentRuleSession(
            ruleLists: contentRuleLists,
            additionalRuleList: contentRuleList
        )
        self.openModifiedLink = openModifiedLink
        self.openPeek = openPeek
        self.handleLinkDrag = handleLinkDrag
        self.splitLinkHost = splitLinkHost
        self.linkDestinationHost = linkDestinationHost
        let httpAuthenticationSession = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: allowsCredentialAccess
                && isCredentialAccessEnabled,
            loadCredential: loadHTTPAuthenticationCredential,
            saveCredential: saveHTTPAuthenticationCredential
        )
        self.httpAuthenticationSession = httpAuthenticationSession
        credentialSession = BrowserCredentialSession(
            spaceID: spaceID,
            supportsAccess: allowsCredentialAccess,
            isEnabled: isCredentialAccessEnabled,
            httpAuthentication: httpAuthenticationSession
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
        #if CREST_CHROMIUM_HOST
        pageEngine = ChromiumNativePage(profileID: profileID)
        #else
        let webViewInterval = Self.lifecycleSignposter.beginInterval("Initialize WKWebView")
        BrowserWebInspectorAccess.enableDeveloperExtras(
            in: configuration.preferences
        )
        BrowserDesktopPictureInPictureAccess.enable(in: configuration.preferences)
        BrowserPictureInPictureContentBridge.shared.install(in: configuration.userContentController)
        let desktopWebView = BrowserDesktopWebView(
            frame: .zero,
            configuration: configuration
        )
        pageEngine = BrowserWebKitPageEngine(webView: desktopWebView)
        desktopWebView.underPageBackgroundColor = .clear
        Self.lifecycleSignposter.endInterval("Initialize WKWebView", webViewInterval)
        #endif
        super.init()
        // The Space's default zoom. WebKit takes it from its view below; other
        // engines replay it when their page is created.
        if webKitView == nil { pageEngine.setZoom(pageZoom) }
        if webKitView == nil, let mediaSessionStore, let transport = pageEngine.mediaSessionTransport {
            mediaSessionCoordinator = BrowserMediaSessionPageCoordinator(
                transport: transport,
                endpoint: self,
                store: mediaSessionStore,
                owner: { [weak self] in
                    self?.navigationContext.map {
                        BrowserTabRuntimeAssignment(
                            tabID: $0.tabID, spaceID: $0.spaceID, profileID: $0.spaceAssignment.profileID)
                    }
                },
                fallbackTitle: { [weak self] in
                    guard let self else { return nil }
                    return self.navigationContext?.mediaSessionOwnerTitle(observedPageTitle: self.title)
                        ?? BrowserTab.resolvedCustomTitle(self.title)
                }
            )
        }
        // An engine that runs Crest's content bridges itself receives them here;
        // WebKit installs its own through the user content controller below.
        if allowsCredentialAccess, let scripting = pageEngine.contentScripting {
            _ = scripting.install(
                BrowserContentScript(
                    source: BrowserCredentialContentBridge.source,
                    handlerName: BrowserCredentialContentBridge.messageHandlerName,
                    mainFrameOnly: false
                )
            ) { [weak self] message in
                guard let self else { return }
                self.credentialSession.receive(message.body, from: message.frame, topLevelURL: self.url)
            }
        }
        #if CREST_CHROMIUM_HOST
        chromiumPage?.observer = { [weak self] event, values in
            self?.receiveChromiumEvent(event, values: values)
        }
        chromiumPage?.linkHandler = { [weak self] action, destination, label in
            guard let self, let context = self.navigationContext else { return false }
            // A selection search carries its text as the label; it goes where the
            // WebKit menu's does, with the Space's own search provider.
            if action == "can_search" || action == "search" {
                let source = BrowserTabRuntimeAssignment(
                    tabID: context.tabID, spaceID: context.spaceID, profileID: context.assignment.profileID)
                guard let search = self.linkDestinationHost.selectionSearch(for: label, from: source) else { return false }
                guard action == "search" else { return true }
                return self.linkDestinationHost.openLink(
                    search.url, from: search.source,
                    in: BrowserSpaceRuntimeAssignment(spaceID: source.spaceID, profileID: source.profileID))
            }
            guard BrowserExternalURLPolicy.accepts(destination) else { return false }
            switch action {
            case "can_peek": return true
            case "peek":
                self.openPeek(BrowserPeekRequest(url: destination, sourceTabID: context.tabID,
                    sourceTitle: context.title, spaceAssignment: context.assignment,
                    trigger: .contextMenu))
                return true
            // The engine asks while AppKit holds the main thread building the
            // menu, so availability answers from store state. The action runs
            // the same shared command the WebKit menu route uses.
            case "can_split": return self.splitLinkHost.canOpenLink(context.tabID, context.assignment)
            case "split":
                self.openLinkInSplitView(destination)
                return true
            case "drag": return self.linkDrag?.beginNativeLink(url: destination, label: label) == true
            default: return false
            }
        }
        linkDrag?.observeNativeMouseDown()
        chromiumPage?.protectedLinkHandler = { [weak self] destination in
            guard let self, let context = self.navigationContext,
                let sourceWindow = self.pageEngine.nativeView.window,
                let request = BrowserPeekPolicy.request(destinationURL: destination, context: context,
                    isUserActivatedLink: true, isTopLevelNavigation: true, isAlternateModified: false)
            else { return nil }
            // The engine cancels first, then invokes this action after leaving
            // its navigation stack. A moved/reassigned source must not open Peek.
            return { [weak self, weak sourceWindow] in
                guard let self, let sourceWindow, self.pageEngine.nativeView.window === sourceWindow,
                    let current = self.navigationContext,
                    current.tabID == context.tabID, current.assignment == context.assignment,
                    current.placement == context.placement, current.savedURL == context.savedURL,
                    current.automaticallyOpensPeek else { return }
                self.openPeek(request)
            }
        }
        chromiumPage?.modifiedLinkHandler = { [weak self] destination, modifiers, token in
            guard let self else { return (.navigate, nil) }
            let preferences = BrowserLinkPreferenceStore.shared.preferences
            let decision = BrowserLinkNavigationDecision.classifyModifiedLink(
                destinationURL: destination, context: self.navigationContext,
                isUserActivatedLink: true, isTopLevelNavigation: true,
                isCommandModified: modifiers & 1 != 0, isOptionModified: modifiers & 2 != 0,
                isMiddleClick: modifiers & 8 != 0, peekModifier: preferences.peekClickModifier,
                isShiftModified: modifiers & 4 != 0,
                focusesNewTabs: self.opensModifiedLinksInForeground || preferences.focusesNewTabsOpenedFromLinks)
            guard decision == .peekModifier else { return (decision, nil) }
            guard let context = self.navigationContext, let sourceWindow = self.pageEngine.nativeView.window,
                let request = decision.peekRequest(destinationURL: destination, context: context,
                    engineNavigation: BrowserEngineNavigation(
                        implementation: self.pageEngine.registration.implementationId, token: token))
            else { return (.navigate, nil) }
            return (decision, { [weak self, weak sourceWindow] in
                guard let self, let sourceWindow, self.pageEngine.nativeView.window === sourceWindow,
                    let current = self.navigationContext,
                    current.tabID == context.tabID, current.assignment == context.assignment else {
                    self?.chromiumPage?.discardNavigation(token)
                    return
                }
                self.openPeek(request)
            })
        }
        #else
        let webView = desktopWebView
        desktopWebView.menuHost = self
        desktopWebView.linkHover = linkHover
        desktopWebView.linkDrag = linkDrag
        if normalizedDefaultPageZoom != BrowserPageZoomPolicy.defaultLevel {
            webView.pageZoom = normalizedDefaultPageZoom
        }
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        if let mediaSessionStore {
            let coordinator = BrowserMediaSessionPageCoordinator(
                webView: webView,
                endpoint: self,
                store: mediaSessionStore,
                owner: { [weak self] in
                    self?.navigationContext.map {
                        BrowserTabRuntimeAssignment(
                            tabID: $0.tabID,
                            spaceID: $0.spaceID,
                            profileID: $0.spaceAssignment.profileID
                        )
                    }
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
            BrowserLinkHoverContentBridge.install(in: webView.configuration.userContentController)
            BrowserLinkDragContentBridge.install(in: webView.configuration.userContentController)
            linkContextMessageProxy = BrowserLinkContextContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak self] message in
                self?.receiveLinkContextMessage(message)
            }
        }
        do {
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
        #endif
    }

    /// Records that web content opened this page and that WebKit still owes it a
    /// navigation. Only a page pool adopting a popup calls this.
    func markOpenedAsPopup() {
        wasOpenedAsPopup = true
        isAwaitingPopupNavigation = true
    }

    func load(_ url: URL) {
        load(URLRequest(url: url))
    }

    func load(_ request: URLRequest) {
        #if CREST_CHROMIUM_HOST
        if let chromiumPage, let destination = request.url {
            pendingNavigationURL = destination
            webContentFailureMessage = nil
            isLoading = true
            pageEngine.load(request)
            return
        }
        #endif
        appInitiatedURL = request.url
        prepareForNavigation(to: request.url)
        pageEngine.load(request)
    }

    /// Replays a request WebKit classified as web-content navigation in this
    /// page without granting it the broader trust of an app-initiated load.
    func loadWebContentRequest(_ request: URLRequest) {
        #if CREST_CHROMIUM_HOST
        if chromiumPage != nil { load(request); return }
        #endif
        prepareForNavigation(to: request.url)
        pageEngine.load(request)
    }

    /// The adapter's tagged, opaque history. Uncommitted pages return nil so
    /// an empty renderer cannot overwrite a useful archive.
    var interactionState: Data? {
        guard pageEngine.registration.supports("interaction-state") else { return nil }
        return pageEngine.interactionState
    }

    /// Lets the adapter restore its own history instead of starting `url` afresh.
    /// Rejected state falls back to an ordinary load; an adapter that queues page
    /// creation also owns that fallback if restoration fails after attachment.
    @discardableResult
    func restoreInteractionState(_ state: Data, expecting url: URL) -> Bool {
        // WebKit owns an adopted popup's first navigation, and an adopted popup
        // has no archived state of its own to restore in the first place.
        guard pageEngine.registration.supports("interaction-state"),
            !isAwaitingPopupNavigation, !wasOpenedAsPopup
        else { return false }
        appInitiatedURL = url
        prepareForNavigation(to: url)
        if webKitView != nil { navigationHistory = BrowserPageNavigationHistory() }
        guard pageEngine.restoreInteractionState(state, expecting: url) else {
            pendingNavigationURL = nil
            return false
        }
        return true
    }

    func monitorUserActivity(_ handler: @escaping () -> Void) {
        userActivityHandler = handler
        // An engine without a user content controller reports input itself.
        guard let webView = webKitView else { return }
        guard ownsUserContentController, userActivityMessageProxy == nil else { return }
        userActivityMessageProxy = BrowserUserActivityBridge.install(
            in: webView.configuration.userContentController
        ) { [weak self] in
            self?.userActivityHandler?()
        }
    }

    func styleVisitedLinks(history: [BrowserHistoryEntry]) async {
        guard let webView = webKitView else { return }
        await BrowserVisitedLinkStyler.apply(history: history, to: webView)
    }

    func stopMonitoringUserActivity() {
        userActivityHandler = nil
    }

    func updateNavigationContext(
        tab: BrowserTab,
        automaticallyOpensPeek: Bool = true
    ) {
        let previousTitle = navigationContext?.title
        let shouldRefreshAutomaticIcon =
            tab.iconMode == .automatic
            && !tab.hasCurrentAutomaticFavicon
            && url != nil
            && !isLoading
        if faviconData != tab.displayFaviconData
            || navigationContext?.iconMode != tab.iconMode
            || navigationContext?.tabID != tab.id
        {
            faviconSession?.invalidate()
            faviconData = tab.displayFaviconData
        }
        navigationContext = BrowserPageNavigationContext(
            tab: tab,
            spaceID: spaceID,
            profileID: profileID,
            automaticallyOpensPeek: automaticallyOpensPeek
        )
        linkDrag?.contextDidChange()
        if previousTitle != navigationContext?.title {
            mediaSessionCoordinator?.ownerTitleDidChange()
        }
        if shouldRefreshAutomaticIcon {
            refreshFavicon()
        }
    }

    func prepareForSpaceDeletion() {
        #if CREST_CHROMIUM_HOST
        chromiumPage?.dispose()
        #endif
        faviconSession?.stop()
        mediaCaptureSession?.reset()
        sitePermissionRequests.setPresentationAvailable(false)
        translation.reset()
        readerModeSession?.invalidate()
        linkHover?.detach()
        linkDrag?.detach()
        (webView as? BrowserDesktopWebView)?.linkHover = nil
        (webView as? BrowserDesktopWebView)?.linkDrag = nil
        focusRestoration.invalidate()
        mediaSessionCoordinator?.prepareForRemoval()
        pictureInPicture?.invalidate()
        fileUploadAccess.invalidate()
        userActivityHandler = nil
        guard let webView = webKitView else { return }
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
            userActivityMessageProxy = nil
            geolocationMessageProxy = nil
            blockedPopupMessageProxy = nil
            geolocationCoordinator = nil
            hostedNotificationMessageProxy = nil
            mediaSessionMessageProxy = nil
            mediaSessionCoordinator = nil
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
        if mediaSessionMessageProxy != nil {
            webView.configuration.userContentController
                .removeScriptMessageHandler(
                    forName: BrowserMediaSessionContentBridge.messageHandlerName,
                    contentWorld: BrowserMediaSessionContentBridge.contentWorld
                )
        }
        mediaSessionMessageProxy = nil
        mediaSessionCoordinator = nil
        userActivityHandler = nil
    }

    func applyContentBlocking(
        policy: BrowserContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        guard let webView = webKitView else { return }
        contentRuleSession.apply(
            policy: policy,
            balancedRuleLists: balancedRuleLists,
            to: webView,
            reloadsImmediately: activation == .immediately && url != nil
        )
    }

    func retryAfterProcessFailure() {
        processRecovery.reset()
        webContentFailureMessage = nil
        pageEngine.reload(bypassingCache: false)
    }

    func presentFind() {
        findSession.present(hasLoadedPage: url != nil)
    }

    @discardableResult
    func showWebInspector() -> Bool {
        pageEngine.showInspector()
    }

    func toggleDeveloperPanel(_ panel: BrowserDeveloperPanel) {
        let result = pageEngine.toggleInspector(panel, current: developerPanel)
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
                let image = await withCheckedContinuation { continuation in
                    pageEngine.capture(rect: rect, width: nil) { continuation.resume(returning: $0) }
                }
                guard let image else { throw BrowserDeveloperCaptureError.pageUnavailable }
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
            guard let self, let window = nativeView.window else { return }
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

    private var findExecutor: any BrowserFindExecuting {
        pageEngine
    }

    func dismissFind() {
        findSession.dismiss(using: findExecutor)
    }

    func find(_ query: String, direction: BrowserFindDirection = .forward) {
        findSession.find(query, direction: direction, using: findExecutor)
    }

    @discardableResult
    func zoomIn() -> Bool {
        guard developerViewport == nil else { return false }
        return setTemporaryPageZoom(BrowserPageZoomPolicy.increased(from: pageZoom))
    }

    @discardableResult
    func zoomOut() -> Bool {
        guard developerViewport == nil else { return false }
        return setTemporaryPageZoom(BrowserPageZoomPolicy.decreased(from: pageZoom))
    }

    @discardableResult
    func resetZoom() -> Bool {
        guard developerViewport == nil else { return false }
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
        await readerModeSession?.refreshAvailability()
    }

    func setReaderModeActive(_ isActive: Bool) async throws {
        guard let readerModeSession else { throw BrowserReaderModeError.articleUnavailable }
        try await readerModeSession.setActive(isActive)
    }

    func toggleReaderMode() {
        readerModeSession?.toggle()
    }

    func respond(to bar: BrowserEngineInfoBar, with response: BrowserEngineInfoBar.Response) {
        // The engine withdraws the bar itself once it has taken the answer.
        if !pageEngine.respondToInfoBar(bar.id, response: response.rawValue) {
            engineInfoBars.removeAll { $0.id == bar.id }
        }
    }

    func dismissCredentialFillRequest() {
        credentialState.dismissFillRequest()
    }

    func setCredentialAccessEnabled(_ isEnabled: Bool) {
        credentialSession.setEnabled(isEnabled)
    }

    func dismissCredentialSaveCandidate() {
        credentialState.dismissSaveCandidate()
    }

    func fillCredential(_ credential: BrowserCredential, for requestID: UUID) async throws {
        if let scripting = pageEngine.contentScripting {
            try await credentialSession.fill(credential, for: requestID) { body, arguments, frame in
                try await scripting.callAsyncJavaScript(body, arguments: arguments, in: frame)
            }
            return
        }
        guard let webView = webKitView else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fill(credential, for: requestID, in: webView)
    }

    func fillGeneratedPassword(_ password: String, for requestID: UUID) async throws {
        if let scripting = pageEngine.contentScripting {
            try await credentialSession.fillGeneratedPassword(password, for: requestID) { body, arguments, frame in
                try await scripting.callAsyncJavaScript(body, arguments: arguments, in: frame)
            }
            return
        }
        guard let webView = webKitView else { throw CredentialVaultError.credentialManagerDisabled }
        try await credentialSession.fillGeneratedPassword(password, for: requestID, in: webView)
    }

    @discardableResult
    func copyPageLink() -> Bool {
        BrowserPageLinkClipboard.copy(url)
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

    private func fullPageSnapshot(snapshotWidth: CGFloat? = nil) async throws -> NSImage {
        guard url != nil, let service = pageEngine.documentServices else {
            throw BrowserDeveloperCaptureError.pageUnavailable
        }
        return try await service.fullPageSnapshot(width: snapshotWidth)
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

    func sharePage() {
        guard let url else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = self
        sharingPicker = picker
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard let self, self.nativeView.window != nil, self.sharingPicker === picker else { return }
            let anchor = NSRect(
                x: self.nativeView.bounds.maxX - 1,
                y: self.nativeView.bounds.maxY - 1,
                width: 1,
                height: 1
            )
            picker.show(relativeTo: anchor, of: self.nativeView, preferredEdge: .minY)
        }
    }

    func printPage() {
        guard !preparingPrint, printOperation == nil, let service = pageEngine.documentServices,
            url != nil, let window = nativeView.window else { return }
        let printInfo = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo.shared
        let jobTitle = title.isEmpty ? url?.host() ?? ProductIdentity.name : title
        preparingPrint = true
        Task { [weak self, weak window] in
            guard let self else { return }
            defer { preparingPrint = false }
            guard let window else { return }
            do {
                let operation = try await service.printOperation(with: printInfo)
                guard nativeView.window === window, window.isVisible else { return }
                operation.jobTitle = jobTitle
                printOperation = operation
                operation.runModal(
                    for: window, delegate: self,
                    didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
            } catch {
                guard window.isVisible else { return }
                Self.postFailureNotice("The page couldn’t be printed.", error: error)
            }
        }
    }

    func pdfData() async throws -> Data {
        guard url != nil, let service = pageEngine.documentServices else { throw BrowserPageExportError.pageUnavailable }
        return try await service.pdfData()
    }

    func exportPDF() {
        guard let window = nativeView.window, url != nil else { return }
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
        guard url != nil, let service = pageEngine.documentServices else { throw BrowserPageExportError.pageUnavailable }
        return try await service.webArchiveData()
    }

    func exportWebArchive() {
        guard let window = nativeView.window, url != nil,
            let service = pageEngine.documentServices else { return }
        let format = service.archiveFormat
        let suggestedFilename = BrowserPageExportPolicy.webArchiveFilename(
            title: title,
            url: url,
            format: format
        )
        Task { [weak self, weak window] in
            guard let self, let window else { return }
            do {
                let data = try await webArchiveData()
                let panel = NSSavePanel()
                panel.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .data]
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
        guard zoom != pageZoom else {
            return false
        }
        pageZoom = zoom
        pageEngine.setZoom(renderedPageZoom)
        return true
    }

    func prepareForNavigation(to url: URL?) {
        // Same-document navigation never commits a replacement document.
        // Cancel the current pull here; suspend new pulls only when WebKit
        // actually starts provisional navigation.
        linkDrag?.cancel()
        mediaCaptureSession?.reset()
        sitePermissionRequests.cancelAll()
        translation.reset()
        readerModeSession?.invalidate()
        pictureInPicture?.invalidate()
        linkHover?.beginNavigation()
        focusRestoration.invalidate()
        mediaSessionCoordinator?.prepareForNavigation()
        beginBlockedPopupNavigation()
        synchronizePopupPermission(for: url)
        faviconSession?.invalidate()
        pendingNavigationURL = url
        // A capture describes one document's DOM. A right-click whose menu
        // never opened — a page that cancelled the event to draw its own —
        // must not survive into the next document.
        linkContextCapture.clear()
        clearNavigationFailure(preservingPendingURL: true)
    }

    func updateUnderPageBackground() {
        webKitView?.underPageBackgroundColor =
            completedNavigationCount == 0 ? .clear : nil
    }

    func recordNavigationFailure(
        _ error: any Error,
        phase: BrowserNavigationFailurePhase,
        navigation: WKNavigation?
    ) {
        guard isCurrentNavigation(navigation) else { return }
        activeNavigation = nil
        let fallbackURL = pendingNavigationURL ?? webKitView?.url ?? url
        pendingNavigationURL = nil
        navigationFailure = BrowserNavigationFailure(
            error: error,
            phase: phase,
            fallbackURL: fallbackURL
        )
        canGoBack = canReturnFromNavigationFailure || (webKitView?.canGoBack ?? false)
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

    #if CREST_CHROMIUM_HOST
    private func receiveChromiumEvent(_ event: String, values: [String: Any]) {
        switch event {
        case "navigation_started":
            linkDrag?.beginNavigation()
            linkHover?.beginNavigation()
            credentialState.didStartNavigation()
            beginBlockedPopupNavigation()
            mediaSessionCoordinator?.prepareForNavigation()
        case "infobar_added":
            guard let bar = BrowserEngineInfoBar(values: values), !engineInfoBars.contains(where: { $0.id == bar.id })
            else { return }
            engineInfoBars.append(bar)
        case "infobar_removed":
            engineInfoBars.removeAll { $0.id == values["id"] as? Int }
        case "media_session":
            if let body = values["body"] { mediaSessionCoordinator?.receive(body, isMainFrame: true) }
        case "user_activity":
            userActivityHandler?()
        case "link_hover":
            linkHover?.receiveEngineHover((values["url"] as? String).flatMap(URL.init(string:)))
        case "popup_blocked":
            guard let raw = values["url"] as? String, let pageURL = URL(string: raw) else { return }
            recordEngineBlockedPopup(pageURL: pageURL, documentIdentifier: "\(committedNavigationCount)")
        case "favicon":
            guard let rawURL = values["url"] as? String, let source = URL(string: rawURL),
                let url, BrowserTabStateRestorePolicy.restoresArchivedState(archivedURL: source, tabURL: url) else { return }
            faviconData = values["data"] as? Data
        case "changed":
            let wasLoading = isLoading
            let destination = (values["url"] as? String).flatMap(URL.init(string:))
            // The host creates a blank WebContents before loading the requested URL.
            if destination?.absoluteString == "about:blank", pendingNavigationURL != nil { return }
            url = destination
            title = values["title"] as? String ?? ""
            isLoading = values["isLoading"] as? Bool ?? false
            if !isLoading {
                linkDrag?.didFinishNavigation()
                // A navigation that failed or turned into a download ends
                // here without committing.
                linkHover?.didFailNavigation()
                mediaSessionCoordinator?.didFinishNavigation()
            }
            estimatedProgress = isLoading ? 0.5 : 1
            hasOnlySecureContent = values["secure"] as? Bool == true
            canGoBack = values["canGoBack"] as? Bool ?? false
            canGoForward = values["canGoForward"] as? Bool ?? false
            // A failure is reported once, by the navigation that failed; the
            // state changes after it do not repeat it. It stays until a
            // navigation commits: the engine retries a network error on its
            // own, and a retry that fails again commits no new error page.
            switch values["failure"] as? String {
            case "process_terminated":
                webContentFailureMessage = "process_terminated"
                credentialState.webContentProcessDidTerminate()
                mediaSessionCoordinator?.webContentProcessDidTerminate()
            case "navigation_failed":
                pendingNavigationURL = nil
                navigationFailure = BrowserNavigationFailure(
                    chromiumNetError: values["errorCode"] as? Int ?? 0, failingURL: destination)
            default: break
            }
            if values["committed"] as? Bool == true {
                pendingNavigationURL = nil
                navigationFailure = nil
                webContentFailureMessage = nil
                linkHover?.didCommitNavigation()
                mediaSessionCoordinator?.didCommitNavigation()
                committedNavigationCount += 1
                synchronizePopupPermission(for: destination)
            }
            if wasLoading, !isLoading, committedNavigationCount > 0 { completedNavigationCount += 1 }
        case "developer_panel":
            // The inspector went away on its own — its close button, an
            // undocked window close, or the engine tearing it down. Without
            // this the next Console command would try to close a panel that is
            // already gone instead of opening one.
            developerPanel = nil
        case "closed":
            Task { @MainActor [weak self] in
                guard let self else { return }
                host?.closeWebContentInitiatedPage(self)
            }
        case "creation_failed":
            isLoading = false
            webContentFailureMessage = "Chromium couldn’t create this page."
        case "open_requested":
            if let value = values["url"] as? String, let destination = URL(string: value) { openModifiedLink(URLRequest(url: destination), spaceID, true) }
        default: break
        }
    }
    #endif

    func refreshNavigationState() {
        #if CREST_CHROMIUM_HOST
        if chromiumPage != nil { return }
        #endif
        synchronizeNavigationHistory()
        canGoBack = canReturnFromNavigationFailure || !navigationHistory.backItems.isEmpty || (webKitView?.canGoBack ?? false)
        canGoForward = !navigationHistory.forwardItems.isEmpty || (webKitView?.canGoForward ?? false)
    }

    func clearNavigationFailure(preservingPendingURL: Bool = false) {
        navigationFailure = nil
        if !preservingPendingURL {
            pendingNavigationURL = nil
        }
        refreshNavigationState()
    }

    private func presentPDFExportError(_ error: Error, in window: NSWindow) {
        Self.postFailureNotice("The page couldn’t be exported.", error: error)
    }

    private func presentWebArchiveExportError(_ error: Error, in window: NSWindow) {
        Self.postFailureNotice("The page couldn’t be saved as a web archive.", error: error)
    }

    /// A failed export or print needs nothing from the person, so it is a
    /// notice rather than an alert.
    private static func postFailureNotice(_ summary: String, error: Error) {
        BrowserNoticeCenter.shared.post(BrowserNotice(
            message: "\(summary) \(error.localizedDescription)",
            systemImage: "exclamationmark.triangle"))
    }

    private func observeWebViewState() {
        guard let webView = webKitView else { return }
        webView.publisher(for: \.url, options: [.initial, .new]).sink { [weak self] _ in
            // WebKit publishes URL before finishing its back-forward-list
            // mutation. Read the settled URL and list together on the next turn.
            Task { @MainActor in
                guard let self else { return }
                let value = self.webKitView?.url
                self.translation.documentURLDidChange(from: self.url, to: value)
                self.url = value
                self.refreshNavigationState()
                self.credentialState.didChangeTopLevelURL(to: value)
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.title, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.recordObservedTitle(value)
                self?.refreshNavigationState()
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.estimatedProgress, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.estimatedProgress = value }
        }
        .store(in: &observations)
        webView.publisher(for: \.isLoading, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated {
                self?.isLoading = value
                self?.refreshNavigationState()
            }
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
            MainActor.assumeIsolated { self?.refreshNavigationState() }
        }
        .store(in: &observations)
        webView.publisher(for: \.canGoForward, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.refreshNavigationState() }
        }
        .store(in: &observations)
    }

    private func recordObservedTitle(_ observedTitle: String?) {
        let normalizedTitle = observedTitle ?? ""
        guard title != normalizedTitle else { return }
        title = normalizedTitle
        mediaSessionCoordinator?.ownerTitleDidChange()
    }

    func refreshFavicon() {
        guard navigationContext?.iconMode == .automatic,
            webKitView?.url != nil
        else { return }
        faviconSession?.refresh()
    }

    func pullFavicon() async -> Data? {
        await faviconSession?.pull()
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
        guard let webView = webKitView else { return }
        credentialSession.receive(scriptMessage, in: webView)
    }

    /// Records the link the person just right-clicked, moments before WebKit
    /// hands AppKit the menu that right-click opens.
    private func receiveLinkContextMessage(_ scriptMessage: WKScriptMessage) {
        guard isOwnScriptMessage(scriptMessage),
            scriptMessage.name
                == BrowserLinkContextContentBridge.messageHandlerName
        else { return }
        if scriptMessage.frameInfo.isMainFrame,
            let activation = BrowserDownloadSourceCapture(
                messageBody: scriptMessage.body
            )
        {
            downloadSourceStore.record(activation)
            return
        }
        linkContextCapture.record(
            body: scriptMessage.body,
            documentURL: scriptMessage.frameInfo.request.url,
            isMainFrame: scriptMessage.frameInfo.isMainFrame
        )
    }


}
