import ObjectiveC
import WebKit

/// The navigation delegate of a page that has ended. WebKit closes a page only
/// when its web view is deallocated, and until then the page's scripts keep
/// running and can still navigate. WebKit commits a navigation to another site
/// in a new process, and a web view whose last release lands during that commit
/// crashes WebKit. This delegate turns down every navigation and response, so
/// nothing commits in the page again, whoever still holds its web view.
@MainActor
final class MobileEndedPageNavigationDelegate: NSObject, WKNavigationDelegate {
    // MARK: - Static Variables

    /// The key the web view keeps its delegate under: WebKit holds a
    /// navigation delegate weakly, and the page that owned the web view is gone.
    private static var ownerKey: UInt8 = 0

    // MARK: - Actions

    /// Takes over the navigation of `webView`, whose page has ended, and
    /// suspends its media, so the page neither loads nor plays again.
    static func takeOver(_ webView: WKWebView) {
        let delegate = MobileEndedPageNavigationDelegate()
        objc_setAssociatedObject(webView, &ownerKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.navigationDelegate = delegate
        webView.setAllMediaPlaybackSuspended(true)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.cancel)
    }
}
