import AppKit
import Combine
import Foundation
import Observation
import UniformTypeIdentifiers
import WebKit
import os

/// The tab-level operations a page needs from whatever owns it. Popup adoption
/// and `window.close()` arrive while a WebKit delegate callback is on the stack;
/// the page itself defers teardown requests until that callback has unwound.
@MainActor
protocol BrowserPageHosting: AnyObject {
    /// Adopts the web view WebKit pre-made for a popup into a new selected tab,
    /// or returns nil when this opener cannot host one.
    func adoptPopupWebView(
        configuration: WKWebViewConfiguration,
        requestedURL: URL?,
        opener: BrowserPage
    ) -> WKWebView?

    /// Honors `window.close()` for a page the web content itself opened.
    func closeWebContentInitiatedPage(_ page: BrowserPage)

    /// Retires an empty transient surface whose initial navigation became a download.
    func discardDownloadOnlyPage(_ page: BrowserPage)
}
