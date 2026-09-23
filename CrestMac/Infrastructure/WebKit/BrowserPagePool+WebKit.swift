import Foundation
import WebKit

/// The pool's WebKit hosting: each WebKit page's configuration, its private
/// website data store and content rules, popups WebKit creates itself, and
/// script messages a popup posts to its opener's shared handlers.
extension BrowserPagePool {
    // MARK: - Actions - Pages

    /// A WebKit page for `space`, or for a popup WebKit configured from its
    /// opener. A popup keeps the opener's configuration, which carries its
    /// website data store, content controller and web extension controller.
    func makeWebKitPageEngine(
        for space: BrowserSpace,
        adoptedConfiguration: WKWebViewConfiguration? = nil
    ) -> any BrowserPageEngineAdapter {
        let contentRuleLists = contentRuleLists(for: space)
        return BrowserWebKitPageAdapter(
            configuration: adoptedConfiguration
                ?? BrowserPageConfiguration.make(
                    for: space.profile,
                    websiteDataStore: websiteDataStore(for: space.profile),
                    contentRuleLists: contentRuleLists
                ),
            contentRuleLists: contentRuleLists,
            ownsUserContentController: adoptedConfiguration == nil
        )
    }

    /// Adopts the web view WebKit pre-made for a popup as a new tab in the
    /// opener's Space, selected unless `selecting` is false.
    ///
    /// Per-Space isolation needs no work here: WebKit derives the popup's
    /// configuration from the opener's, so it already carries the opener's
    /// `websiteDataStore` and web extension controller. The Space lookup only
    /// confirms the tab landed in the opener's own profile.
    func adoptPopupWebView(
        configuration: WKWebViewConfiguration,
        requestedURL: URL?,
        opener: BrowserPage,
        selecting: Bool = true
    ) -> WKWebView? {
        adoptPopupPage(requestedURL: requestedURL, opener: opener, selecting: selecting) { space in
            makeWebKitPageEngine(for: space, adoptedConfiguration: configuration)
        }?.webKitView
    }

    private func contentRuleLists(for space: BrowserSpace) -> [WKContentRuleList] {
        contentBlocking.ruleLists(for: space.browsingPreferences.contentBlockingPolicy)
    }

    private func websiteDataStore(for profile: BrowsingProfile) -> WKWebsiteDataStore? {
        guard usesEphemeralWebsiteDataStores else { return nil }
        if let dataStore = profileDataStores.ephemeral[profile.id] {
            return dataStore
        }
        let dataStore = WKWebsiteDataStore.nonPersistent()
        profileDataStores.ephemeral[profile.id] = dataStore
        return dataStore
    }

    // MARK: - Actions - Content blocking

    func prepareContentBlocking() async {
        await contentBlocking.prepare()
    }

    /// Reloads presented pages only when their Space's protection level changes.
    func reconcileContentBlocking(in session: BrowserSession) async {
        let update = await contentBlocking.reconcile(in: session)
        for (tabID, runtime) in runtimeStore.runtimes {
            let page = runtime.page
            let isPresentedPage = runtimeStore.presentedTabIDs.contains(tabID)
            page.applyContentBlocking(
                policy: update.policy(for: page.spaceID),
                balancedRuleLists: contentBlocking.balancedRuleLists ?? [],
                activation: update.activation(for: page.spaceID, isPresented: isPresentedPage)
            )
        }

        pruneTransientLeases()
        for lease in transientLeases.values.compactMap(\.value) {
            lease.applyContentBlocking(
                policy: update.policy(for: lease.spaceID),
                balancedRuleLists: contentBlocking.balancedRuleLists ?? []
            )
        }
    }

    /// Refreshes rule lists without reloading unchanged documents.
    func reloadContentBlocking(in session: BrowserSession) async {
        contentBlocking.invalidateRuleLists()
        await reconcileContentBlocking(in: session)
    }

    // MARK: - Actions - Script message routing

    // A popup shares its opener's `WKUserContentController`, so its bridges
    // post to the opener's handlers; each message goes to the page whose web
    // view sent it.

    func routeHostedWebNotificationMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveHostedWebNotificationMessage(message)
    }

    func routeGeolocationMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveGeolocationMessage(message)
    }

    func routeBlockedPopupMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveBlockedPopupMessage(message)
    }

    func routeMediaSessionMessage(_ message: WKScriptMessage) {
        residentPage(sending: message)?.receiveMediaSessionMessage(message)
    }

    private func residentPage(sending message: WKScriptMessage) -> BrowserPage? {
        guard let sourceWebView = message.webView else { return nil }
        return residentPages.first { $0.webKitView === sourceWebView }
    }
}
