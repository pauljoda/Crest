import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

/// The tab-level operations a page needs from whatever owns it. Popup adoption
/// and `window.close()` arrive while a WebKit delegate callback is on the stack;
/// the page itself defers teardown requests until that callback has unwound.
@MainActor
protocol MobileBrowserPageHosting: AnyObject {
    /// Activates a foreground tab that a modified link just created and issues
    /// its one app-owned navigation without waiting for a SwiftUI observation
    /// pass to reconcile the new selection.
    func activateOpenedLink(_ url: URL, in session: BrowserSession)

    /// Adopts the web view WebKit pre-made for a popup into a new selected tab,
    /// or returns nil when this opener cannot host one.
    func adoptPopupWebView(
        configuration: WKWebViewConfiguration,
        requestedURL: URL?,
        opener: MobileBrowserPage
    ) -> WKWebView?

    /// Honors `window.close()` for a page the web content itself opened.
    func closeWebContentInitiatedPage(_ page: MobileBrowserPage)

    /// Retires an empty transient surface whose initial navigation became a download.
    func discardDownloadOnlyPage(_ page: MobileBrowserPage)

    /// Routes a pre-iOS 27 geolocation bridge message from a shared popup
    /// content controller to the page whose web view authored it.
    func routeGeolocationMessage(_ message: WKScriptMessage)

    /// Routes a blocked-popup bridge message from a shared popup content
    /// controller to the page whose web view actually authored it.
    func routeBlockedPopupMessage(_ message: WKScriptMessage)

    /// Routes a Media Session message received through an opener's shared
    /// content controller to the resident page that authored it.
    func routeMediaSessionMessage(_ message: WKScriptMessage)
}
