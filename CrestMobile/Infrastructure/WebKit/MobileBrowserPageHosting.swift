import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// The tab-level operations a page needs from whatever owns it. WebKit asks for
/// both while a delegate callback is on the stack, so neither can be deferred.
@MainActor
protocol MobileBrowserPageHosting: AnyObject {
    /// Adopts the web view WebKit pre-made for a popup into a new selected tab,
    /// or returns nil when this opener cannot host one.
    func adoptPopupWebView(
        configuration: WKWebViewConfiguration,
        requestedURL: URL?,
        opener: MobileBrowserPage
    ) -> WKWebView?

    /// Honors `window.close()` for a page the web content itself opened.
    func closeWebContentInitiatedPage(_ page: MobileBrowserPage)
}
