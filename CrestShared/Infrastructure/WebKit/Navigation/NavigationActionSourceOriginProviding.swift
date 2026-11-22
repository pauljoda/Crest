import WebKit

/// Supplies the source origin for navigation-action implementations that do not
/// come from WebKit. `WKNavigationAction` has no valid public initializer, so a
/// synthetic subclass must never ask the inherited `sourceFrame` implementation
/// to read WebKit's missing internal state.
@MainActor
protocol BrowserNavigationActionSourceOriginProviding: AnyObject {
    var browserSourceOrigin: SiteOrigin? { get }
}

extension WKNavigationAction {
    /// The origin that asked for the navigation. WebKit annotates
    /// `sourceFrame` as non-null and every real request has one, so it is read
    /// as an optional purely so a missing frame falls back to the page at
    /// `currentURL` instead of trapping. A frame WebKit reports without a host
    /// — an `about:blank` or sandboxed frame — takes the same fallback, which
    /// is the origin a prompt would name anyway.
    @MainActor
    func requestingOrigin(fallingBackTo currentURL: URL?) -> SiteOrigin? {
        let fallback = currentURL.flatMap(SiteOrigin.init(url:))
        if let provider = self as? any BrowserNavigationActionSourceOriginProviding {
            return provider.browserSourceOrigin ?? fallback
        }
        let frame: WKFrameInfo? = sourceFrame
        guard let frame else { return fallback }
        let frameOrigin = SiteOrigin(frame.securityOrigin)
        return frameOrigin.host.isEmpty ? fallback : frameOrigin
    }
}
