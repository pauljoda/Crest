import Foundation
import WebKit

@MainActor
final class BrowserPopupCoordinator {
    /// Routes a popup destination another application owns into the
    /// external-scheme consent path.
    typealias ExternalSchemeHandOff =
        @MainActor (
            URL,
            BrowserPopupTrigger,
            BrowserSiteOrigin?
        ) -> Void

    private let openNewTab: (URL) -> Void
    private let handOffExternalScheme: ExternalSchemeHandOff

    init(
        openNewTab: @escaping (URL) -> Void,
        handOffExternalScheme: @escaping ExternalSchemeHandOff = { _, _, _ in }
    ) {
        self.openNewTab = openNewTab
        self.handOffExternalScheme = handOffExternalScheme
    }

    /// Resolves one new-window request while WebKit waits. `adopt` receives the
    /// requested URL — nil for `window.open()` without a destination — and
    /// returns the web view WebKit created from its own configuration, or nil
    /// when the opener cannot host an adopted popup (a Peek or Quick Window
    /// lease, or a pool without a tab host). A declined adoption still opens the
    /// destination as a plain tab so the request is never silently dropped.
    func resolveOpen(
        for navigationAction: WKNavigationAction,
        currentURL: URL?,
        adopt: (URL?) -> WKWebView?
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let destinationURL = navigationAction.request.url

        // The scheme settles first, before any tab exists. A destination another
        // app owns goes straight to the hand-off consent path, and one nothing may
        // open is dropped — neither leaves a tab behind.
        switch BrowserPopupSchemeRouting.classify(destinationURL: destinationURL) {
        case .popupPolicy:
            break
        case .blocked:
            return nil
        case .handOffToSystem(let url):
            handOffExternalScheme(
                url,
                BrowserPopupTrigger.classify(navigationAction.navigationType),
                sourceOrigin(for: navigationAction, currentURL: currentURL)
            )
            return nil
        }

        // WebKit has already enforced its user-activation / automatic-window
        // preference before this delegate runs. Every request that reaches here
        // must be adopted synchronously so `window.opener`, about:blank, and the
        // identity provider's return channel survive.
        if let popupWebView = adopt(destinationURL) {
            return popupWebView
        }
        if let destinationURL {
            openNewTab(destinationURL)
        }
        return nil
    }

    /// The origin that asked for the window. WebKit annotates `sourceFrame` as
    /// non-null and every real popup has one, so it is read as an optional purely
    /// so a missing frame falls back to the page the user is looking at instead of
    /// trapping. A frame WebKit reports without a host — `about:blank`, a
    /// sandboxed frame — takes the same fallback, which is the origin a prompt
    /// would name anyway.
    private func sourceOrigin(
        for navigationAction: WKNavigationAction,
        currentURL: URL?
    ) -> BrowserSiteOrigin? {
        if let provider = navigationAction
            as? any BrowserNavigationActionSourceOriginProviding
        {
            return provider.browserSourceOrigin
                ?? currentURL.flatMap(BrowserSiteOrigin.init(url:))
        }
        let sourceFrame: WKFrameInfo? = navigationAction.sourceFrame
        if let sourceFrame {
            let frameOrigin = BrowserSiteOrigin(sourceFrame.securityOrigin)
            if !frameOrigin.host.isEmpty {
                return frameOrigin
            }
        }
        return currentURL.flatMap(BrowserSiteOrigin.init(url:))
    }
}
