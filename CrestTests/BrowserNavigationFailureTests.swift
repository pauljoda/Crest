import AppKit
import SwiftUI
import WebKit
import XCTest

@testable import Crest

final class BrowserNavigationFailureClassificationTests: XCTestCase {
    func testClassifiesCommonConnectionFailuresWithStableDiagnostics() throws {
        let url = try XCTUnwrap(URL(string: "https://status.example.test/report"))

        let timeout = try XCTUnwrap(
            BrowserNavigationFailure(
                error: URLError(.timedOut),
                phase: .provisional,
                fallbackURL: url
            )
        )
        XCTAssertEqual(timeout.kind, .timedOut)
        XCTAssertEqual(timeout.failingURL, url)
        XCTAssertEqual(timeout.browserCode, "CREST_TIMED_OUT")
        XCTAssertEqual(timeout.errorDomain, NSURLErrorDomain)
        XCTAssertEqual(timeout.errorCode, URLError.timedOut.rawValue)

        let offline = try XCTUnwrap(
            BrowserNavigationFailure(
                error: URLError(.notConnectedToInternet),
                phase: .provisional,
                fallbackURL: url
            )
        )
        XCTAssertEqual(offline.kind, .offline)
        XCTAssertEqual(offline.browserCode, "CREST_INTERNET_DISCONNECTED")

        let secureConnection = try XCTUnwrap(
            BrowserNavigationFailure(
                error: URLError(.serverCertificateUntrusted),
                phase: .provisional,
                fallbackURL: url
            )
        )
        XCTAssertEqual(secureConnection.kind, .secureConnectionFailed)
        XCTAssertEqual(secureConnection.browserCode, "CREST_CERTIFICATE_INVALID")
    }

    func testUsesTheFailingURLReportedByURLLoading() throws {
        let fallbackURL = try XCTUnwrap(URL(string: "https://fallback.example.test"))
        let failingURL = try XCTUnwrap(URL(string: "https://actual.example.test/path"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cannotFindHost.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        let failure = try XCTUnwrap(
            BrowserNavigationFailure(
                error: error,
                phase: .provisional,
                fallbackURL: fallbackURL
            )
        )

        XCTAssertEqual(failure.kind, .cannotFindServer)
        XCTAssertEqual(failure.failingURL, failingURL)
        XCTAssertEqual(failure.displayHost, "actual.example.test")
    }

    func testIgnoresExpectedNavigationInterruptions() {
        XCTAssertNil(
            BrowserNavigationFailure(
                error: URLError(.cancelled),
                phase: .provisional,
                fallbackURL: URL(string: "https://example.test")
            )
        )
        XCTAssertNil(
            BrowserNavigationFailure(
                error: NSError(domain: "WebKitErrorDomain", code: 102),
                phase: .provisional,
                fallbackURL: URL(string: "https://example.test")
            )
        )
        XCTAssertNil(
            BrowserNavigationFailure(
                error: WKError(.webContentProcessTerminated),
                phase: .committed,
                fallbackURL: URL(string: "https://example.test")
            )
        )
    }
}

@MainActor
final class BrowserNavigationFailureViewTests: XCTestCase {
    func testFailureAccentUsesTheSpacePrimaryOrItsOnlyBackgroundColor() {
        let multicolor = BrowserSpaceBranding(colors: [.ink, .ocean, .gold])
        let singleColor = BrowserSpaceBranding(colors: [.ember])

        XCTAssertEqual(
            BrowserNavigationFailureAppearance.brandColor(for: multicolor),
            .ocean
        )
        XCTAssertEqual(
            BrowserNavigationFailureAppearance.brandColor(for: singleColor),
            .ember
        )
        XCTAssertNil(BrowserNavigationFailureAppearance.brandColor(for: nil))
    }

    func testFailureBackgroundUsesOneUniformFillAtEveryCorner() throws {
        let url = try XCTUnwrap(URL(string: "https://offline.example.test"))
        let failure = try XCTUnwrap(
            BrowserNavigationFailure(
                error: URLError(.cannotConnectToHost),
                phase: .provisional,
                fallbackURL: url
            )
        )
        let renderedSize = CGSize(width: 800, height: 800)
        let renderer = ImageRenderer(
            content: BrowserNavigationFailureView(
                failure: failure,
                branding: BrowserSpaceBranding(colors: [.ink, .ocean]),
                layout: .regular,
                canGoBack: false,
                canProceed: false,
                retry: {},
                goBack: {},
                proceed: {}
            )
            .frame(width: renderedSize.width, height: renderedSize.height)
            .environment(\.colorScheme, .dark)
        )
        renderer.scale = 1

        let image = try XCTUnwrap(renderer.nsImage)
        let imageData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: imageData))
        let inset = 20
        let samplePoints = [
            NSPoint(x: inset, y: inset),
            NSPoint(x: Int(renderedSize.width) - inset, y: inset),
            NSPoint(x: inset, y: Int(renderedSize.height) - inset),
            NSPoint(
                x: Int(renderedSize.width) - inset,
                y: Int(renderedSize.height) - inset
            ),
        ]
        let samples = try samplePoints.map { point in
            let color = try XCTUnwrap(
                bitmap.colorAt(x: Int(point.x), y: Int(point.y))
            )
            return try XCTUnwrap(color.usingColorSpace(.deviceRGB))
        }
        let reference = try XCTUnwrap(samples.first)

        for sample in samples.dropFirst() {
            XCTAssertEqual(sample.redComponent, reference.redComponent, accuracy: 0.01)
            XCTAssertEqual(sample.greenComponent, reference.greenComponent, accuracy: 0.01)
            XCTAssertEqual(sample.blueComponent, reference.blueComponent, accuracy: 0.01)
            XCTAssertEqual(sample.alphaComponent, reference.alphaComponent, accuracy: 0.01)
        }
    }
}

@MainActor
final class BrowserPageNavigationFailureTests: XCTestCase {
    private var navigationSource: WKWebView?

    func testDesktopPagePublishesAndRetriesAProvisionalFailure() throws {
        let page = try makePage()
        let failingURL = try XCTUnwrap(URL(string: "https://offline.example.test/path"))
        let error = NSError(
            domain: NSURLErrorDomain,
            code: URLError.cannotConnectToHost.rawValue,
            userInfo: [NSURLErrorFailingURLErrorKey: failingURL]
        )

        page.webView(
            page.webView,
            didFailProvisionalNavigation: nil,
            withError: error
        )

        XCTAssertEqual(page.navigationFailure?.kind, .cannotConnect)
        XCTAssertEqual(page.navigationFailure?.phase, .provisional)
        XCTAssertEqual(page.displayURL, failingURL)
        XCTAssertFalse(page.canReturnFromNavigationFailure)

        page.retryAfterNavigationFailure()

        XCTAssertNil(page.navigationFailure)
        XCTAssertEqual(page.pendingNavigationURL, failingURL)
        XCTAssertEqual(page.displayURL, failingURL)
    }

    func testDesktopPageDoesNotPublishCancelledLoads() throws {
        let page = try makePage()

        page.webView(
            page.webView,
            didFailProvisionalNavigation: nil,
            withError: URLError(.cancelled)
        )

        XCTAssertNil(page.navigationFailure)
    }

    func testDesktopPageIgnoresAStaleFailureAfterTheNavigationFinished() throws {
        let page = try makePage()
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

    func testDesktopPageReportsCommitBeforeNavigationFinishes() throws {
        let page = try makePage()
        let navigation = try makeNavigation()

        page.webView(page.webView, didStartProvisionalNavigation: navigation)
        page.webView(page.webView, didCommit: navigation)

        XCTAssertEqual(page.committedNavigationCount, 1)
        XCTAssertEqual(page.completedNavigationCount, 0)
    }

    func testDesktopPageIgnoresAFailureFromASupersededNavigation() throws {
        let page = try makePage()
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

    func testDesktopPageRecordsAFailureForTheActiveNavigation() throws {
        let page = try makePage()
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

    func testDesktopPageFollowsAServerRedirectInTheDisplayedURL() throws {
        let page = try makePage()
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

    func testDesktopPageIgnoresAServerRedirectForASupersededNavigation() throws {
        let page = try makePage()
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

    func testDesktopPageHandsOffAnExternalSchemeWithoutAnErrorPage() throws {
        let page = try makePage()
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

        // WebKit answers a policy cancel with a frame-load interruption, which
        // must never become one of Crest's error pages.
        page.webView(
            page.webView,
            didFailProvisionalNavigation: nil,
            withError: NSError(domain: "WebKitErrorDomain", code: 102)
        )

        XCTAssertNil(page.navigationFailure)
        XCTAssertNil(page.displayURL)
    }

    /// Mints a real navigation object. WebKit owns navigation identity, so the
    /// tests drive the delegate with navigations a web view actually created.
    private func makeNavigation() throws -> WKNavigation {
        let source =
            navigationSource
            ?? WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        navigationSource = source
        return try XCTUnwrap(source.loadHTMLString("<html></html>", baseURL: nil))
    }

    private func makePage() throws -> BrowserPage {
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
        let pool = BrowserPagePool()
        pool.select(tab: tab, space: space)
        return try XCTUnwrap(pool.activePage)
    }
}

private final class RedirectingWebViewStub: WKWebView {
    var redirectedURL: URL?

    override var url: URL? { redirectedURL }
}

/// WebKit never lets an app build a real `WKNavigationAction`, so the external
/// hand-off test stands in for the one WebKit hands to the policy delegate.
private final class StubExternalNavigationAction: WKNavigationAction,
    BrowserNavigationActionSourceOriginProviding
{
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
