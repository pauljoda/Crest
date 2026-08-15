import XCTest
import WebKit
@testable import Crest

final class BrowserVisitedLinkStylerTests: XCTestCase {
    func testStylingIsLimitedToGoogleSearchResults() throws {
        XCTAssertTrue(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "https://www.google.com/search?q=crest"))
            )
        )
        XCTAssertTrue(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "https://google.co.uk/search?q=crest"))
            )
        )
        XCTAssertFalse(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "https://www.google.com/chrome/"))
            )
        )
        XCTAssertFalse(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "https://example.com/search?q=crest"))
            )
        )
    }

    func testVisitedURLPayloadUsesOnlyNormalizedWebHistory() throws {
        let history = [
            BrowserHistoryEntry(
                url: try XCTUnwrap(URL(string: "https://arc.net/#download")),
                title: "Arc",
                firstVisitedAt: .now,
                lastVisitedAt: .now
            ),
            BrowserHistoryEntry(
                url: try XCTUnwrap(URL(string: "file:///tmp/private")),
                title: "Local",
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        ]

        XCTAssertEqual(
            BrowserVisitedLinkStyler.normalizedVisitedURLStrings(history),
            ["https://arc.net/"]
        )
    }

    @MainActor
    func testStylerPaintsAMatchingGoogleResultInThePageDOM() async throws {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let navigation = VisitedLinkNavigationWaiter(webView: webView)
        webView.navigationDelegate = navigation
        webView.loadHTMLString(
            """
            <a href="https://example.com/visited?utm_source=google"><h3 id="result">Visited result</h3></a>
            """,
            baseURL: try XCTUnwrap(
                URL(string: "https://www.google.com/search?q=crest")
            )
        )
        try await navigation.waitForCompletion()

        await BrowserVisitedLinkStyler.apply(
            history: [
                BrowserHistoryEntry(
                    url: try XCTUnwrap(URL(string: "https://example.com/visited?hl=en")),
                    title: "Visited result",
                    firstVisitedAt: .now,
                    lastVisitedAt: .now
                )
            ],
            to: webView
        )

        let color = try await webView.callAsyncJavaScript(
            "return getComputedStyle(document.querySelector('#result')).color",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
        XCTAssertEqual(color, "rgb(184, 140, 255)")
    }

    @MainActor
    func testStylerDoesNotTreatEveryGoogleSearchAsTheSameDestination() async throws {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let navigation = VisitedLinkNavigationWaiter(webView: webView)
        webView.navigationDelegate = navigation
        webView.loadHTMLString(
            """
            <a href="https://www.google.com/search?q=other"><h3 id="result">Other search</h3></a>
            """,
            baseURL: try XCTUnwrap(
                URL(string: "https://www.google.com/search?q=crest")
            )
        )
        try await navigation.waitForCompletion()

        await BrowserVisitedLinkStyler.apply(
            history: [
                BrowserHistoryEntry(
                    url: try XCTUnwrap(URL(string: "https://www.google.com/search?q=visited")),
                    title: "Visited search",
                    firstVisitedAt: .now,
                    lastVisitedAt: .now
                )
            ],
            to: webView
        )

        let color = try await webView.callAsyncJavaScript(
            "return getComputedStyle(document.querySelector('#result')).color",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
        XCTAssertNotEqual(color, "rgb(184, 140, 255)")
    }
}

@MainActor
private final class VisitedLinkNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    init(webView: WKWebView) {
        self.webView = webView
    }

    func waitForCompletion() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
