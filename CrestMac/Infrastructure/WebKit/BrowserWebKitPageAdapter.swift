import AppKit
import Combine
import Foundation
import WebKit

/// The desktop WebKit adapter for one page: the `BrowserDesktopWebView`, its
/// delegates and user content controller bridges, and the page controllers
/// built on the web view. The page's WebKit delegate conformances read their
/// per-page WebKit state from here.
@MainActor
final class BrowserWebKitPageAdapter: BrowserPageEngineAdapter {
    // MARK: - Variables

    let webKit: BrowserWebKitPageEngine
    let webView: BrowserDesktopWebView
    var engine: any BrowserPageEngine { webKit }
    var engineIdentifier: String? { nil }

    /// False when this page shares the opener's `WKUserContentController`, which
    /// every popup does: WebKit copies the opener's configuration and the copy
    /// keeps the same controller. Installing the same script message handler
    /// twice on it throws, and removing one would strip it from the opener.
    let ownsUserContentController: Bool
    var activeNavigation: WKNavigation?
    let contentRuleSession: BrowserPageContentRuleSession
    var geolocationCoordinator: BrowserGeolocationCoordinator?
    private let geolocationService: any BrowserGeolocationServicing
    private let recoverGeolocationSystemAuthorization: BrowserGeolocationCoordinator.RecoverSystemAuthorization?
    private weak var page: BrowserPage?
    private var observations: Set<AnyCancellable> = []
    private var credentialMessageProxy: BrowserCredentialScriptMessageProxy?
    private var linkContextMessageProxy: BrowserLinkContextScriptMessageProxy?
    private var userActivityMessageProxy: BrowserUserActivityScriptMessageProxy?
    private var geolocationMessageProxy: BrowserGeolocationScriptMessageProxy?
    private var blockedPopupMessageProxy: BrowserBlockedPopupScriptMessageProxy?
    private var mediaSessionMessageProxy: BrowserMediaSessionScriptMessageProxy?
    private var hostedNotificationMessageProxy: BrowserHostedWebNotificationScriptMessageProxy?

    private(set) lazy var pictureInPicture: BrowserPictureInPicturePageController? =
        BrowserPictureInPicturePageController(webView: webView)
    private(set) lazy var linkHover: BrowserLinkHoverController? = BrowserLinkHoverController(webView: webView)
    private(set) lazy var linkDrag: BrowserLinkDragController? = BrowserLinkDragController(
        webView: webView,
        context: { [weak self] in self?.page?.navigationContext },
        handle: { [weak self] event in self?.page?.handleLinkDrag(event) }
    )
    private(set) lazy var readerModeSession: BrowserReaderModeSession? = page.map {
        BrowserReaderModeSession(
            document: BrowserWebKitReaderModeDocument(webView: webView, translation: $0.translation))
    }
    private(set) lazy var faviconSession: BrowserFaviconSession? = page.map {
        BrowserFaviconSession(
            document: BrowserWebKitFaviconDocument(webView: webView, profileID: $0.profileID),
            policy: .delayedDocumentIcons,
            receive: { [weak self] in self?.page?.receive(.favicon($0, source: nil)) }
        )
    }
    private(set) lazy var mediaCaptureSession: BrowserMediaCaptureSession? = page.map {
        BrowserMediaCaptureSession(webView: webView, permissionCenter: $0.permissionCenter, spaceID: $0.spaceID)
    }

    var isContentBlockingActive: Bool { contentRuleSession.isActive }
    var credentialEvaluator: BrowserCredentialSession.Evaluate? {
        BrowserCredentialSession.evaluator(in: webView)
    }

    // MARK: - Initializers

    init(
        configuration: WKWebViewConfiguration,
        contentRuleList: WKContentRuleList? = nil,
        contentRuleLists: [WKContentRuleList] = [],
        ownsUserContentController: Bool = true,
        geolocationService: any BrowserGeolocationServicing = BrowserGeolocationSystemService(),
        recoverGeolocationSystemAuthorization: BrowserGeolocationCoordinator.RecoverSystemAuthorization? = nil
    ) {
        let interval = BrowserPage.lifecycleSignposter.beginInterval("Initialize WKWebView")
        BrowserWebInspectorAccess.enableDeveloperExtras(in: configuration.preferences)
        BrowserDesktopPictureInPictureAccess.enable(in: configuration.preferences)
        BrowserPictureInPictureContentBridge.shared.install(in: configuration.userContentController)
        webView = BrowserDesktopWebView(frame: .zero, configuration: configuration)
        webKit = BrowserWebKitPageEngine(webView: webView)
        webView.underPageBackgroundColor = .clear
        BrowserPage.lifecycleSignposter.endInterval("Initialize WKWebView", interval)
        contentRuleSession = BrowserPageContentRuleSession(
            ruleLists: contentRuleLists,
            additionalRuleList: contentRuleList
        )
        self.ownsUserContentController = ownsUserContentController
        self.geolocationService = geolocationService
        self.recoverGeolocationSystemAuthorization = recoverGeolocationSystemAuthorization
    }

    // MARK: - Actions - Lifecycle

    func makeMediaSessionCoordinator(
        for page: BrowserPage,
        store: BrowserMediaSessionStore
    ) -> BrowserMediaSessionPageCoordinator? {
        if ownsUserContentController {
            mediaSessionMessageProxy = BrowserMediaSessionContentBridge.install(
                in: webView.configuration.userContentController
            ) { [weak page] message in
                page?.receiveMediaSessionMessage(message)
            }
        }
        return BrowserMediaSessionPageCoordinator(
            webView: webView, endpoint: page, store: store,
            owner: page.mediaSessionOwner, fallbackTitle: page.mediaSessionFallbackTitle)
    }

    func attach(to page: BrowserPage, allowsCredentialAccess: Bool) {
        self.page = page
        webView.menuHost = page
        webView.linkHover = linkHover
        webView.linkDrag = linkDrag
        webView.isInspectable = true
        webView.navigationDelegate = page
        webView.uiDelegate = page
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        observeWebViewState()
        let controller = webView.configuration.userContentController
        if allowsCredentialAccess, ownsUserContentController {
            credentialMessageProxy = BrowserCredentialContentBridge.install(in: controller) { [weak page] message in
                page?.receiveCredentialMessage(message)
            }
        }
        // Private and isolated launches split exactly like a standard one, and
        // the bridge reports a destination rather than storing anything, so the
        // only gate is the shared-controller one every bridge has: a popup runs
        // its opener's scripts against its opener's handlers.
        if ownsUserContentController {
            BrowserLinkHoverContentBridge.install(in: controller)
            BrowserLinkDragContentBridge.install(in: controller)
            linkContextMessageProxy = BrowserLinkContextContentBridge.install(in: controller) { [weak page] message in
                page?.receiveLinkContextMessage(message)
            }
            blockedPopupMessageProxy = BrowserBlockedPopupContentBridge.install(in: controller) { [weak page] message in
                page?.receiveBlockedPopupMessage(message)
            }
        }
        let dialogPresenter = page.dialogPresenter
        geolocationCoordinator = BrowserGeolocationCoordinator(
            webView: webView,
            permissionCenter: page.permissionCenter,
            service: geolocationService,
            spaceID: page.spaceID,
            spaceName: page.spaceName,
            prompt: { [weak page] origin, topLevelURL, requestedSpaceName in
                guard let page else { return .denyOnce }
                return await page.sitePermissionRequests.response(
                    to: .location, origin: origin,
                    topLevelOrigin: topLevelURL.flatMap(BrowserSiteOrigin.init(url:)) ?? origin,
                    spaceName: requestedSpaceName
                )
            },
            recoverSystemAuthorization:
                recoverGeolocationSystemAuthorization
                ?? { await dialogPresenter.recoverGeolocationSystemAuthorization() }
        )
        if ownsUserContentController {
            geolocationMessageProxy = BrowserGeolocationContentBridge.install(in: controller) { [weak page] message in
                page?.receiveGeolocationMessage(message)
            }
        }
        if page.hostedNotificationCenter != nil, ownsUserContentController {
            hostedNotificationMessageProxy = BrowserHostedWebNotificationContentBridge.install(
                in: controller
            ) { [weak page] message in
                page?.receiveHostedWebNotificationMessage(message)
            }
        }
    }

    func detach(from page: BrowserPage) {
        webView.linkHover = nil
        webView.linkDrag = nil
        mediaCaptureSession?.reset()
        page.downloadCenter.resetAutomaticDownloadSequence(in: webView)
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.menuHost = nil
        observations.removeAll()
        page.removeGeolocationRequests()
        page.removeHostedWebNotifications()
        defer { geolocationCoordinator = nil }
        guard ownsUserContentController else {
            // A popup shares its opener's content controller. Removing handlers
            // here would silence them for the opener too.
            credentialMessageProxy = nil
            linkContextMessageProxy = nil
            userActivityMessageProxy = nil
            geolocationMessageProxy = nil
            blockedPopupMessageProxy = nil
            hostedNotificationMessageProxy = nil
            mediaSessionMessageProxy = nil
            return
        }
        let controller = webView.configuration.userContentController
        func remove(_ proxy: AnyObject?, name: String, world: WKContentWorld) {
            guard proxy != nil else { return }
            controller.removeScriptMessageHandler(forName: name, contentWorld: world)
        }
        remove(
            credentialMessageProxy, name: BrowserCredentialContentBridge.messageHandlerName,
            world: BrowserCredentialContentBridge.contentWorld)
        credentialMessageProxy = nil
        remove(
            linkContextMessageProxy, name: BrowserLinkContextContentBridge.messageHandlerName,
            world: BrowserLinkContextContentBridge.contentWorld)
        linkContextMessageProxy = nil
        remove(
            userActivityMessageProxy, name: BrowserUserActivityBridge.messageHandlerName,
            world: BrowserUserActivityBridge.contentWorld)
        userActivityMessageProxy = nil
        remove(
            geolocationMessageProxy, name: BrowserGeolocationContentBridge.messageHandlerName,
            world: BrowserGeolocationContentBridge.contentWorld)
        geolocationMessageProxy = nil
        remove(
            blockedPopupMessageProxy, name: BrowserBlockedPopupContentBridge.messageHandlerName,
            world: BrowserBlockedPopupContentBridge.contentWorld)
        blockedPopupMessageProxy = nil
        remove(
            hostedNotificationMessageProxy, name: BrowserHostedWebNotificationContentBridge.messageHandlerName,
            world: BrowserHostedWebNotificationContentBridge.contentWorld)
        hostedNotificationMessageProxy = nil
        remove(
            mediaSessionMessageProxy, name: BrowserMediaSessionContentBridge.messageHandlerName,
            world: BrowserMediaSessionContentBridge.contentWorld)
        mediaSessionMessageProxy = nil
    }

    // MARK: - Actions - Page services

    func install(_ focusRestoration: BrowserWebFocusRestorationController) {
        webView.focusRestoration = focusRestoration
    }

    func monitorUserActivity(for page: BrowserPage) {
        guard ownsUserContentController, userActivityMessageProxy == nil else { return }
        userActivityMessageProxy = BrowserUserActivityBridge.install(
            in: webView.configuration.userContentController
        ) { [weak page] in
            page?.receive(.userActivity)
        }
    }

    func styleVisitedLinks(history: [BrowserHistoryEntry]) async {
        await BrowserVisitedLinkStyler.apply(history: history, to: webView)
    }

    func prepareForNavigation() {
        mediaCaptureSession?.reset()
    }

    /// A private WebKit page is private through its website data store.
    func setPrivateBrowsing(_ isPrivate: Bool) {}

    /// WebKit hands Crest a popup's web view through `createWebViewWith`
    /// instead; it never names a page it created.
    func adoptEngineCreatedPage(_ token: String) -> Bool { false }

    func applyContentBlocking(
        policy: BrowserContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        reloadsImmediately: Bool
    ) {
        contentRuleSession.apply(
            policy: policy,
            balancedRuleLists: balancedRuleLists,
            to: webView,
            reloadsImmediately: reloadsImmediately
        )
    }

    // MARK: - Actions - Observation

    private func observeWebViewState() {
        webView.publisher(for: \.url, options: [.initial, .new]).sink { [weak self] _ in
            // WebKit publishes URL before finishing its back-forward-list
            // mutation. Read the settled URL and list together on the next turn.
            Task { @MainActor in
                guard let self else { return }
                self.page?.receive(.urlChanged(self.webView.url))
            }
        }
        .store(in: &observations)
        webView.publisher(for: \.title, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.page?.receive(.titleChanged(value)) }
        }
        .store(in: &observations)
        webView.publisher(for: \.estimatedProgress, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.page?.receive(.progressChanged(value)) }
        }
        .store(in: &observations)
        webView.publisher(for: \.isLoading, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.page?.receive(.loadingChanged(value)) }
        }
        .store(in: &observations)
        webView.publisher(for: \.hasOnlySecureContent, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.page?.receive(.secureContentChanged(value)) }
        }
        .store(in: &observations)
        webView.publisher(for: \.themeColor, options: [.initial, .new]).sink { [weak self] value in
            MainActor.assumeIsolated { self?.page?.receive(.themeColorChanged(value)) }
        }
        .store(in: &observations)
        webView.publisher(for: \.canGoBack, options: [.initial, .new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.page?.receive(.historyChanged) }
        }
        .store(in: &observations)
        webView.publisher(for: \.canGoForward, options: [.initial, .new]).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.page?.receive(.historyChanged) }
        }
        .store(in: &observations)
    }
}
