import AppKit
import Foundation
import WebKit

/// The page's WebKit-only state, read by its WebKit delegate conformances and
/// bridges. Each is empty when another engine hosts the page.
extension BrowserPage {
    /// A page hosted by a desktop `WKWebView` built from `configuration`.
    convenience init(
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
        self.init(
            engine: BrowserWebKitPageAdapter(
                configuration: configuration,
                contentRuleList: contentRuleList,
                contentRuleLists: contentRuleLists,
                ownsUserContentController: ownsUserContentController,
                geolocationService: geolocationService,
                recoverGeolocationSystemAuthorization: recoverGeolocationSystemAuthorization
            ),
            dialogPresenter: dialogPresenter,
            downloadCenter: downloadCenter,
            permissionCenter: permissionCenter,
            hostedNotificationCenter: hostedNotificationCenter,
            recoverNotificationSystemAuthorization: recoverNotificationSystemAuthorization,
            serverTrustOverrides: serverTrustOverrides,
            mediaSessionStore: mediaSessionStore,
            spaceID: spaceID,
            profileID: profileID,
            spaceName: spaceName,
            allowsCredentialAccess: allowsCredentialAccess,
            isCredentialAccessEnabled: isCredentialAccessEnabled,
            defaultPageZoom: defaultPageZoom,
            loadHTTPAuthenticationCredential: loadHTTPAuthenticationCredential,
            saveHTTPAuthenticationCredential: saveHTTPAuthenticationCredential,
            openNewTab: openNewTab,
            openModifiedLink: openModifiedLink,
            openPeek: openPeek,
            handleLinkDrag: handleLinkDrag,
            splitLinkHost: splitLinkHost,
            linkDestinationHost: linkDestinationHost,
            opensExternalURL: opensExternalURL
        )
    }

    var webKitAdapter: BrowserWebKitPageAdapter? { engineAdapter as? BrowserWebKitPageAdapter }
    var webKitView: WKWebView? { webKitAdapter?.webView }

    var activeNavigation: WKNavigation? {
        get { webKitAdapter?.activeNavigation }
        set { webKitAdapter?.activeNavigation = newValue }
    }

    /// Supplemental history for link entries WebKit leaves out of its lists.
    var navigationHistory: BrowserPageNavigationHistory {
        get { webKitAdapter?.webKit.history ?? BrowserPageNavigationHistory() }
        set { webKitAdapter?.webKit.history = newValue }
    }

    var geolocationCoordinator: BrowserGeolocationCoordinator? { webKitAdapter?.geolocationCoordinator }
    var mediaCaptureSession: BrowserMediaCaptureSession? { webKitAdapter?.mediaCaptureSession }

    func applyContentBlocking(
        policy: BrowserContentBlockingPolicy,
        balancedRuleLists: [WKContentRuleList],
        activation: BrowserContentRuleListActivation = .onNextNavigation
    ) {
        webKitAdapter?.applyContentBlocking(
            policy: policy,
            balancedRuleLists: balancedRuleLists,
            reloadsImmediately: activation == .immediately && url != nil
        )
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
        recordNavigationFailure(error, phase: phase, currentURL: webKitView?.url)
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

    /// Whether this page's own web view sent `scriptMessage`.
    ///
    /// A popup shares its opener's `WKUserContentController`, so the opener's
    /// user scripts run inside the popup's document and post to the opener's
    /// handlers. Without this check a popup's form would be read against the
    /// opener's top-level origin, and an accepted fill would be evaluated in the
    /// opener's web view against a frame belonging to the popup's.
    private func isOwnScriptMessage(_ scriptMessage: WKScriptMessage) -> Bool {
        scriptMessage.webView === webKitView
    }

    func receiveCredentialMessage(_ scriptMessage: WKScriptMessage) {
        guard let webView = webKitView else { return }
        credentialSession.receive(scriptMessage, in: webView)
    }

    /// Records the link the person just right-clicked, moments before WebKit
    /// hands AppKit the menu that right-click opens.
    func receiveLinkContextMessage(_ scriptMessage: WKScriptMessage) {
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
