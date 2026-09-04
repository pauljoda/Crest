import AppKit
import Foundation
import WebKit

/// Runs `chrome.identity.launchWebAuthFlow` in a Crest-owned web view.
///
/// Chrome does not own `chromiumapp.org`; it watches its own web view for the
/// first navigation to `https://<extension id>.chromiumapp.org` and cancels
/// it, so the redirect — and the authorization code in its query — never
/// reaches the network. This host does the same thing.
///
/// The web view is built on the Space's own `WKWebsiteDataStore`, the store
/// the person's tabs and that Space's extension pages already share. That is
/// the whole point: a provider the person is signed in to answers a
/// `prompt=none` authorization silently, so an extension that keeps its tokens
/// in `chrome.storage.session` re-authenticates on launch instead of asking
/// for a password Crest has no business seeing.
@MainActor
final class BrowserExtensionWebAuthFlowHost: BrowserExtensionWebAuthFlowHosting {
    static let windowSize = NSSize(width: 520, height: 720)

    private let websiteDataStore: (SpaceID) -> WKWebsiteDataStore?
    private let profile: (SpaceID) -> BrowsingProfile?
    private let anchorWindow: () -> NSWindow?
    /// Held weakly on purpose: this reports whether a flow is still alive, and
    /// a strong reference would make the answer always yes.
    private weak var activeSession: BrowserExtensionWebAuthFlowSession?

    /// Whether a flow — and therefore a web view on somebody's cookie jar —
    /// is still running.
    var isRunningFlow: Bool { activeSession != nil }

    init(
        websiteDataStore: @escaping (SpaceID) -> WKWebsiteDataStore?,
        profile: @escaping (SpaceID) -> BrowsingProfile?,
        anchorWindow: @escaping () -> NSWindow? = { NSApp.keyWindow ?? NSApp.mainWindow }
    ) {
        self.websiteDataStore = websiteDataStore
        self.profile = profile
        self.anchorWindow = anchorWindow
    }

    func runWebAuthFlow(
        _ request: BrowserExtensionWebAuthFlowRequest
    ) async throws -> URL {
        guard let profile = profile(request.spaceID),
            let store = websiteDataStore(request.spaceID)
        else {
            throw BrowserExtensionIdentityBrokerError.pageLoadFailure
        }
        let configuration = BrowserPageConfiguration.make(
            for: profile,
            websiteDataStore: store
        ) { configuration in
            // Crest's pages suspend when detached from a visible window. A
            // non-interactive flow is deliberately never presented, and the
            // providers this exists for redirect from JavaScript, so a
            // suspended web view would turn every silent refresh into the
            // timeout it is supposed to avoid.
            configuration.preferences.inactiveSchedulingPolicy = .none
        }
        let session = BrowserExtensionWebAuthFlowSession(
            request: request,
            configuration: configuration,
            anchorWindow: anchorWindow()
        )
        activeSession = session
        return try await session.run()
    }
}

/// One flow: a window, a web view, and the single answer they resolve to.
///
/// The session settles exactly once and tears everything down on the way out,
/// whichever of the four endings arrives first — the redirect, a load failure,
/// the person closing the window, or the non-interactive deadline.
@MainActor
private final class BrowserExtensionWebAuthFlowSession: NSObject {
    private let request: BrowserExtensionWebAuthFlowRequest
    private let configuration: WKWebViewConfiguration
    private weak var anchorWindow: NSWindow?
    private var continuation: CheckedContinuation<URL, any Error>?
    private var webView: WKWebView?
    private var window: NSWindow?
    private var timeout: Task<Void, Never>?
    /// Set the moment the callback is recognized, before the navigation that
    /// carries it is cancelled. WebKit reports Crest's own cancellation
    /// through the failure delegate, and without this the flow would report a
    /// load failure for the navigation that actually completed it.
    private var resolvedRedirect: URL?
    private var isSettled = false

    init(
        request: BrowserExtensionWebAuthFlowRequest,
        configuration: WKWebViewConfiguration,
        anchorWindow: NSWindow?
    ) {
        self.request = request
        self.configuration = configuration
        self.anchorWindow = anchorWindow
    }

    func run() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    private func start() {
        // No window until there is something to show. A non-interactive flow
        // never makes one, so a silent refresh leaves no invisible
        // authorization window behind at all; the web view runs detached,
        // which the configuration's scheduling policy makes safe.
        let webView = WKWebView(
            frame: NSRect(origin: .zero, size: BrowserExtensionWebAuthFlowHost.windowSize),
            configuration: configuration
        )
        webView.navigationDelegate = self
        webView.isInspectable = true
        self.webView = webView
        if !request.isInteractive {
            startNonInteractiveTimeout()
        }
        webView.load(URLRequest(url: request.url))
    }

    private func positionWindow(_ window: NSWindow) {
        guard let anchorWindow else {
            window.center()
            return
        }
        let anchor = anchorWindow.frame
        window.setFrameOrigin(
            NSPoint(
                x: anchor.midX - window.frame.width / 2,
                y: anchor.midY - window.frame.height / 2
            )
        )
    }

    private func startNonInteractiveTimeout() {
        timeout = Task { @MainActor [weak self] in
            guard let seconds = self?.request.nonInteractiveTimeout else { return }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.settle(.failure(BrowserExtensionIdentityBrokerError.interactionRequired))
        }
    }

    /// Shows the window once a page meant to be looked at has finished
    /// loading, which is Chrome's rule: an interactive flow that redirects
    /// straight through never flashes a window at the person.
    private func present() {
        guard request.isInteractive, window == nil, let webView else { return }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: BrowserExtensionWebAuthFlowHost.windowSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = request.extensionDisplayName
        window.contentView = webView
        window.delegate = self
        self.window = window
        positionWindow(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private func settle(_ result: Result<URL, any Error>) {
        guard !isSettled else { return }
        isSettled = true
        timeout?.cancel()
        timeout = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        window?.delegate = nil
        window?.contentView = nil
        window?.close()
        window = nil
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    /// Whether `url` is the redirect this flow is waiting for. The URL is
    /// never logged: matching it is the only thing done with it before it is
    /// handed back to the extension that asked for it.
    private func isRedirect(_ url: URL?) -> Bool {
        guard let url else { return false }
        return BrowserExtensionIdentityRedirectOrigin.matches(
            url,
            origin: request.redirectOrigin
        )
    }
}

extension BrowserExtensionWebAuthFlowSession: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, isRedirect(url) else {
            decisionHandler(.allow)
            return
        }
        resolvedRedirect = url
        decisionHandler(.cancel)
        settle(.success(url))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        guard let url = navigationResponse.response.url, isRedirect(url) else {
            decisionHandler(.allow)
            return
        }
        resolvedRedirect = url
        decisionHandler(.cancel)
        settle(.success(url))
    }

    func webView(
        _ webView: WKWebView,
        didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
    ) {
        // WebKit re-asks the policy delegate for a server redirect, so this is
        // the belt to that braces: a redirect chain that ends at the callback
        // without another policy decision still finishes the flow.
        guard let url = webView.url, isRedirect(url) else { return }
        resolvedRedirect = url
        settle(.success(url))
    }

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        guard !isSettled else { return }
        if request.isInteractive {
            present()
            return
        }
        // Chrome terminates a non-interactive flow the moment a page finishes
        // loading, unless the caller asked for the JavaScript-redirect
        // allowance — then only the deadline ends it.
        if request.abortsOnLoadForNonInteractive {
            settle(.failure(BrowserExtensionIdentityBrokerError.interactionRequired))
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        failNavigation(error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        failNavigation(error)
    }

    /// An interrupted navigation is not a failed one, and WebKit reports both
    /// through these delegate methods.
    ///
    /// Two interruptions are normal here and neither ends the flow: the
    /// cancellation Crest itself asks for when it recognizes the callback, and
    /// the one a provider causes by calling `location.replace` while its own
    /// page is still parsing — which is precisely the flow this exists to
    /// serve. So the verdict waits one turn, and a web view that has already
    /// started the next navigation is still trying rather than finished.
    private func failNavigation(_ error: any Error) {
        guard !isSettled, resolvedRedirect == nil else { return }
        let error = error as NSError
        guard !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self, !self.isSettled, self.resolvedRedirect == nil,
                self.webView?.isLoading != true
            else { return }
            self.settle(.failure(BrowserExtensionIdentityBrokerError.pageLoadFailure))
        }
    }
}

extension BrowserExtensionWebAuthFlowSession: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        settle(.failure(BrowserExtensionIdentityBrokerError.userRejected))
    }
}
