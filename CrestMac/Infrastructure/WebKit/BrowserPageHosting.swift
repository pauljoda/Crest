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
    /// Replaces an extension document with its top-level web destination in
    /// the same browser tab and ordinary WebKit runtime.
    func replaceExtensionPageNavigation(
        _ page: BrowserPage,
        with destinationURL: URL
    )

    /// Keeps an allowed new-window request in its current transient surface,
    /// or declines when the opener belongs to an ordinary resident tab.
    func navigatePopupInCurrentPage(
        _ request: URLRequest,
        opener: BrowserPage
    ) -> Bool

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

    /// Brings the live tab that authored a clicked system notification forward.
    func activateNotificationSourcePage(_ page: BrowserPage)

    /// Routes a message received by a shared popup content controller to the
    /// page whose web view actually authored it.
    func routeHostedWebNotificationMessage(_ message: WKScriptMessage)

    /// Routes a pre-macOS 27 geolocation bridge message from a shared popup
    /// content controller to the page whose web view authored it.
    func routeGeolocationMessage(_ message: WKScriptMessage)

    /// Routes a blocked-popup bridge message from a shared popup content
    /// controller to the page whose web view actually authored it.
    func routeBlockedPopupMessage(_ message: WKScriptMessage)

    /// Routes a Media Session message received through an opener's shared
    /// content controller to the resident page that authored it.
    func routeMediaSessionMessage(_ message: WKScriptMessage)
}
