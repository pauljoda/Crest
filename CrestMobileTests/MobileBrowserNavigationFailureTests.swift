import WebKit
import XCTest
@testable import CrestMobile

@MainActor
final class MobileBrowserNavigationFailureTests: XCTestCase {
    private var navigationSource: WKWebView?

    func testMobilePagePublishesAndRetriesACommittedFailure() throws {
        let page = makePage()
        let failingURL = try XCTUnwrap(URL(string: "https://interrupted.example.test/path"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.networkConnectionLost.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        page.webView(page.webView, didFail: nil, withError: error)

        XCTAssertEqual(page.navigationFailure?.kind, .connectionLost)
        XCTAssertEqual(page.navigationFailure?.phase, .committed)
        XCTAssertEqual(page.displayURL, failingURL)

        page.retryAfterNavigationFailure()

        XCTAssertNil(page.navigationFailure)
        XCTAssertEqual(page.pendingNavigationURL, failingURL)
        XCTAssertEqual(page.displayURL, failingURL)
    }

    func testMobilePageClearsAFailureWhenAnotherNavigationStarts() throws {
        let page = makePage()
        let failingURL = try XCTUnwrap(URL(string: "https://missing.example.test"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.dnsLookupFailed.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )
        page.webView(
            page.webView,
            didFailProvisionalNavigation: nil,
            withError: error
        )
        XCTAssertNotNil(page.navigationFailure)

        page.webView(page.webView, didStartProvisionalNavigation: nil)

        XCTAssertNil(page.navigationFailure)
    }

    func testMobilePageIgnoresAStaleFailureAfterTheNavigationFinished() throws {
        let page = makePage()
        let navigation = try makeNavigation()

        page.webView(page.webView, didStartProvisionalNavigation: navigation)
        page.webView(page.webView, didFinish: navigation)

        XCTAssertEqual(page.completedNavigationCount, 1)

        page.webView(
            page.webView,
            didFail: navigation,
            withError: URLError(.networkConnectionLost)
        )

        XCTAssertNil(page.navigationFailure)
    }

    func testMobilePageIgnoresAFailureFromASupersededNavigation() throws {
        let page = makePage()
        let superseded = try makeNavigation()
        let current = try makeNavigation()

        page.webView(page.webView, didStartProvisionalNavigation: superseded)
        page.webView(page.webView, didStartProvisionalNavigation: current)
        page.webView(
            page.webView,
            didFailProvisionalNavigation: superseded,
            withError: URLError(.cannotConnectToHost)
        )

        XCTAssertNil(page.navigationFailure)
    }

    func testMobilePageRecordsAFailureForTheActiveNavigation() throws {
        let page = makePage()
        let navigation = try makeNavigation()
        let failingURL = try XCTUnwrap(URL(string: "https://unreachable.example.test/path"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cannotConnectToHost.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        page.webView(page.webView, didStartProvisionalNavigation: navigation)
        page.webView(
            page.webView,
            didFailProvisionalNavigation: navigation,
            withError: error
        )

        XCTAssertEqual(page.navigationFailure?.kind, .cannotConnect)
        XCTAssertEqual(page.navigationFailure?.phase, .provisional)
        XCTAssertEqual(page.displayURL, failingURL)
    }

    func testMobilePageFollowsAServerRedirectInTheDisplayedURL() throws {
        let page = makePage()
        let requestedURL = try XCTUnwrap(URL(string: "https://short.example.test/start"))
        let redirectedURL = try XCTUnwrap(URL(string: "https://destination.example.test/final"))
        let navigation = try makeNavigation()
        page.load(requestedURL)
        page.webView(page.webView, didStartProvisionalNavigation: navigation)

        XCTAssertEqual(page.pendingNavigationURL, requestedURL)
        XCTAssertEqual(page.displayURL, requestedURL)

        let redirectingWebView = RedirectingWebViewStub(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        redirectingWebView.redirectedURL = redirectedURL
        page.webView(
            redirectingWebView,
            didReceiveServerRedirectForProvisionalNavigation: navigation
        )

        XCTAssertEqual(page.pendingNavigationURL, redirectedURL)
        XCTAssertEqual(page.displayURL, redirectedURL)
    }

    func testMobilePageIgnoresAServerRedirectForASupersededNavigation() throws {
        let page = makePage()
        let requestedURL = try XCTUnwrap(URL(string: "https://short.example.test/start"))
        let superseded = try makeNavigation()
        let current = try makeNavigation()
        page.webView(page.webView, didStartProvisionalNavigation: superseded)
        page.load(requestedURL)
        page.webView(page.webView, didStartProvisionalNavigation: current)

        let redirectingWebView = RedirectingWebViewStub(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        redirectingWebView.redirectedURL = try XCTUnwrap(
            URL(string: "https://destination.example.test/final")
        )
        page.webView(
            redirectingWebView,
            didReceiveServerRedirectForProvisionalNavigation: superseded
        )

        XCTAssertEqual(page.pendingNavigationURL, requestedURL)
    }

    func testMobilePageHandsOffAnExternalSchemeWithoutAnErrorPage() throws {
        let page = makePage()
        let mailURL = try XCTUnwrap(URL(string: "mailto:person@example.com"))
        let recorder = PolicyRecorder()

        // A scripted trigger keeps this test from launching a real mail client:
        // the hand-off is refused before anything reaches the system, and the
        // cancel that WebKit sees is the same one a user-approved hand-off uses.
        page.webView(
            page.webView,
            decidePolicyFor: StubExternalNavigationAction(
                url: mailURL,
                navigationType: .other
            )
        ) { recorder.policy = $0 }

        XCTAssertEqual(recorder.policy, .cancel)
        XCTAssertNil(page.pendingNavigationURL)

        page.webView(
            page.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "WebKitErrorDomain", code: 102)
        )

        XCTAssertNil(page.navigationFailure)
    }

    /// Mints a real navigation object. WebKit owns navigation identity, so the
    /// tests drive the delegate with navigations a web view actually created.
    private func makeNavigation() throws -> WKNavigation {
        let source = navigationSource
            ?? WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        navigationSource = source
        return try XCTUnwrap(source.loadHTMLString("<html></html>", baseURL: nil))
    }

    private func makePage() -> MobileBrowserPage {
        let tab = BrowserTab(title: "Blank", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Test",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
        return MobileBrowserPage(
            tab: tab,
            space: space,
            loadsInitialURL: false,
            openNewTab: { _ in }
        )
    }
}

private final class RedirectingWebViewStub: WKWebView {
    var redirectedURL: URL?

    override var url: URL? { redirectedURL }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so the external
/// hand-off test stands in for the one WebKit hands to the policy delegate.
private final class StubExternalNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding {
    private let stubRequest: URLRequest
    private let stubNavigationType: WKNavigationType

    init(url: URL, navigationType: WKNavigationType) {
        stubRequest = URLRequest(url: url)
        stubNavigationType = navigationType
        super.init()
    }

    override var request: URLRequest { stubRequest }
    override var navigationType: WKNavigationType { stubNavigationType }
    override var targetFrame: WKFrameInfo? { nil }
    var browserSourceOrigin: BrowserSiteOrigin? { nil }
}

/// A `@Sendable` decision handler cannot capture a mutable local, so the policy
/// WebKit is handed lands in a box the test can read afterwards.
@MainActor
private final class PolicyRecorder {
    var policy: WKNavigationActionPolicy?
}
