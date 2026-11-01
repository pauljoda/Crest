import WebKit

extension WKWebView {
    // MARK: - Static Variables

    private static let viewScaleKey = "viewScale"
    private static let hasViewScale =
        instancesRespond(to: NSSelectorFromString("_viewScale"))
        && instancesRespond(to: NSSelectorFromString("_setViewScale:"))

    // MARK: - Variables

    /// The scale a page is shown at: its zoom.
    ///
    /// On iOS the public page zoom shrinks a page inside the width it laid out
    /// for, leaving the rest of the view blank. The view scale WebKit gives
    /// Safari lays the page out wider and fits it to the view instead, the
    /// way the Mac's page zoom does. A WebKit without it falls back to the
    /// page zoom.
    var pageScale: CGFloat {
        get {
            #if os(iOS)
                if Self.hasViewScale, let scale = value(forKey: Self.viewScaleKey) as? CGFloat { return scale }
            #endif
            return pageZoom
        }
        set {
            #if os(iOS)
                if Self.hasViewScale {
                    setValue(newValue, forKey: Self.viewScaleKey)
                    return
                }
            #endif
            pageZoom = newValue
        }
    }
}
