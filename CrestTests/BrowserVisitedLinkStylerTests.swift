import AppKit
import WebKit
import XCTest

@testable import Crest

final class BrowserVisitedLinkStylerTests: XCTestCase {
    func testStylingSupportsEveryWebPage() throws {
        XCTAssertTrue(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "https://www.google.com/search?q=crest"))
            )
        )
        XCTAssertTrue(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "https://www.google.com/chrome/"))
            )
        )
        XCTAssertTrue(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "https://example.com/search?q=crest"))
            )
        )
        XCTAssertTrue(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "http://localhost:8080/results"))
            )
        )
        XCTAssertFalse(
            BrowserVisitedLinkStyler.supports(
                try XCTUnwrap(URL(string: "file:///tmp/results.html"))
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
            ),
        ]

        XCTAssertEqual(
            BrowserVisitedLinkStyler.normalizedVisitedURLStrings(history),
            ["https://arc.net/"]
        )
    }

    @MainActor
    func testStylerHighlightsAMatchingLinkWithoutExposingHistoryToThePage() async throws {
        let webView = try await webView(
            html:
                """
                <style>
                  a:link { color: rgb(12, 34, 56); }
                  a:visited { color: rgb(184, 140, 255); }
                </style>
                <a id="result" href="https://example.com/visited?utm_source=crest">
                  Visited result
                </a>
                """,
            baseURL: try XCTUnwrap(URL(string: "https://news.example.org/article"))
        )
        let originalStyle = try await styleAttribute(of: "#result", in: webView)
        let visitedURL = try XCTUnwrap(
            URL(string: "https://example.com/visited?utm_source=crest")
        )

        await BrowserVisitedLinkStyler.apply(
            history: [
                BrowserHistoryEntry(
                    url: visitedURL,
                    title: "Visited result",
                    firstVisitedAt: .now,
                    lastVisitedAt: .now
                )
            ],
            to: webView
        )

        let computedColor = try await computedColor(of: "#result", in: webView)
        let finalStyle = try await styleAttribute(of: "#result", in: webView)
        let pageWorldHistoryGlobalType = try await pageWorldHistoryGlobalType(in: webView)
        let pageWorldContainsHighlight = try await pageWorldContainsCrestHighlight(in: webView)
        let pageWorldMatchesVisited = try await pageWorldMatchesVisited(
            selector: "#result",
            in: webView
        )
        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: webView))
        XCTAssertEqual(computedColor, "rgb(12, 34, 56)")
        XCTAssertEqual(finalStyle, originalStyle)
        XCTAssertEqual(pageWorldHistoryGlobalType, "undefined")
        XCTAssertFalse(pageWorldContainsHighlight)
        XCTAssertFalse(pageWorldMatchesVisited)
    }

    @MainActor
    func testStylerDoesNotPaintSamePathWithDifferentQuery() async throws {
        let webView = try await googleResultsWebView(
            """
            <a href="https://example.com/visited?utm_source=google"><h3 id="result">Unvisited result</h3></a>
            """
        )

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

        let unmatchedURL = try XCTUnwrap(
            URL(string: "https://example.com/visited?utm_source=google")
        )
        XCTAssertFalse(BrowserVisitedLinkStyler.containsVisitedURL(unmatchedURL, in: webView))
    }

    @MainActor
    func testStylerMatchesRedirectFragmentsAndCanonicalURLsExactly() async throws {
        let webView = try await googleResultsWebView(
            """
            <a href="https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fvisited%3Fhl%3Den"><h3 id="wrapper">Wrapped exact result</h3></a>
            <a href="https://example.com/visited?hl=en#section"><h3 id="fragment">Fragment variation</h3></a>
            <a href="https://EXAMPLE.com:443/visited?hl=en"><h3 id="canonical">Canonical variation</h3></a>
            <a href="https://example.com/visited?hl=%65n"><h3 id="encoded">Distinct encoded query</h3></a>
            """
        )

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

        let wrapperURL = try XCTUnwrap(
            URL(
                string:
                    "https://www.google.com/url?q=https%3A%2F%2Fexample.com%2Fvisited%3Fhl%3Den"
            )
        )
        let fragmentURL = try XCTUnwrap(
            URL(string: "https://example.com/visited?hl=en#section")
        )
        let canonicalURL = try XCTUnwrap(
            URL(string: "https://example.com/visited?hl=en")
        )
        let encodedURL = try XCTUnwrap(
            URL(string: "https://example.com/visited?hl=%65n")
        )
        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(wrapperURL, in: webView))
        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(fragmentURL, in: webView))
        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(canonicalURL, in: webView))
        XCTAssertFalse(BrowserVisitedLinkStyler.containsVisitedURL(encodedURL, in: webView))
    }

    @MainActor
    func testRestylingRestoresSiteColorWhenHistoryNoLongerMatches() async throws {
        let webView = try await googleResultsWebView(
            """
            <a href="https://example.com/visited?hl=en">
              <h3 id="result" style="color: rgb(12, 34, 56); -webkit-text-fill-color: rgb(12, 34, 56)">Visited result</h3>
            </a>
            """
        )
        let history = [
            BrowserHistoryEntry(
                url: try XCTUnwrap(URL(string: "https://example.com/visited?hl=en")),
                title: "Visited result",
                firstVisitedAt: .now,
                lastVisitedAt: .now
            )
        ]

        await BrowserVisitedLinkStyler.apply(history: history, to: webView)
        let visitedURL = try XCTUnwrap(URL(string: "https://example.com/visited?hl=en"))
        let visitedComputedColor = try await computedColor(of: "#result", in: webView)
        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: webView))
        XCTAssertEqual(visitedComputedColor, "rgb(12, 34, 56)")

        await BrowserVisitedLinkStyler.apply(history: [], to: webView)
        let clearedComputedColor = try await computedColor(of: "#result", in: webView)
        XCTAssertFalse(BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: webView))
        XCTAssertEqual(clearedComputedColor, "rgb(12, 34, 56)")
    }

    @MainActor
    func testMutationStylingKeepsDynamicQueryVariantUnvisited() async throws {
        let webView = try await googleResultsWebView(
            """
            <style>
              body { margin: 0; background: white; }
              a:link { color: rgb(0, 0, 255); }
              a:visited { color: rgb(184, 140, 255); }
              h3 { font: bold 64px sans-serif; margin: 8px; }
            </style>
            <main id="results"></main>
            """
        )
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

        _ = try await webView.callAsyncJavaScript(
            """
            document.querySelector('#results').innerHTML = `
              <a href="https://example.com/visited?hl=en"><h3 id="exact">Exact result</h3></a>
              <a href="https://example.com/visited?utm_source=google"><h3 id="query">Query variant</h3></a>
            `;
            return true;
            """,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )

        let exactURL = try XCTUnwrap(URL(string: "https://example.com/visited?hl=en"))
        let variantURL = try XCTUnwrap(
            URL(string: "https://example.com/visited?utm_source=google")
        )
        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(exactURL, in: webView))
        XCTAssertFalse(BrowserVisitedLinkStyler.containsVisitedURL(variantURL, in: webView))
        let pixels = try await renderedPixels(in: webView)
        XCTAssertGreaterThan(pixelCount(near: (184, 140, 255), in: pixels), 20)
        XCTAssertGreaterThan(pixelCount(near: (0, 0, 255), in: pixels), 20)
    }

    @MainActor
    func testStylerDoesNotTreatEveryGoogleSearchAsTheSameDestination() async throws {
        let webView = try await googleResultsWebView(
            """
            <a href="https://www.google.com/search?q=other"><h3 id="result">Other search</h3></a>
            """
        )

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

        let otherSearchURL = try XCTUnwrap(URL(string: "https://www.google.com/search?q=other"))
        XCTAssertFalse(
            BrowserVisitedLinkStyler.containsVisitedURL(otherSearchURL, in: webView)
        )
    }

    @MainActor
    func testVisitedStateIsIsolatedBetweenWebViews() async throws {
        let workWebView = try await webView(
            html: "<a href=\"https://example.com/visited\">Work link</a>",
            baseURL: try XCTUnwrap(URL(string: "https://work.example.org/"))
        )
        let personalWebView = try await webView(
            html: "<a href=\"https://example.com/visited\">Personal link</a>",
            baseURL: try XCTUnwrap(URL(string: "https://personal.example.org/"))
        )
        let visitedURL = try XCTUnwrap(URL(string: "https://example.com/visited"))

        await BrowserVisitedLinkStyler.apply(
            history: [
                BrowserHistoryEntry(
                    url: visitedURL,
                    title: "Visited result",
                    firstVisitedAt: .now,
                    lastVisitedAt: .now
                )
            ],
            to: workWebView
        )

        XCTAssertTrue(BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: workWebView))
        XCTAssertFalse(
            BrowserVisitedLinkStyler.containsVisitedURL(visitedURL, in: personalWebView)
        )
    }

    @MainActor
    private func googleResultsWebView(_ html: String) async throws -> WKWebView {
        try await webView(
            html: html,
            baseURL: try XCTUnwrap(URL(string: "https://www.google.com/search?q=crest"))
        )
    }

    @MainActor
    private func webView(html: String, baseURL: URL) async throws -> WKWebView {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600))
        let navigation = VisitedLinkNavigationWaiter(webView: webView)
        webView.navigationDelegate = navigation
        webView.loadHTMLString(html, baseURL: baseURL)
        try await navigation.waitForCompletion()
        return webView
    }

    @MainActor
    private func computedColor(of selector: String, in webView: WKWebView) async throws
        -> String?
    {
        try await webView.callAsyncJavaScript(
            "return getComputedStyle(document.querySelector(selector)).color",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    @MainActor
    private func styleAttribute(of selector: String, in webView: WKWebView) async throws
        -> String?
    {
        try await webView.callAsyncJavaScript(
            "return document.querySelector(selector).getAttribute('style')",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    @MainActor
    private func pageWorldHistoryGlobalType(in webView: WKWebView) async throws -> String? {
        try await webView.callAsyncJavaScript(
            "return typeof globalThis.__crestVisitedURLs",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? String
    }

    @MainActor
    private func pageWorldContainsCrestHighlight(in webView: WKWebView) async throws -> Bool {
        try await webView.callAsyncJavaScript(
            "return CSS.highlights?.has('crest-visited') ?? false",
            arguments: [:],
            in: nil,
            contentWorld: .page
        ) as? Bool ?? false
    }

    @MainActor
    private func pageWorldMatchesVisited(selector: String, in webView: WKWebView) async throws
        -> Bool
    {
        try await webView.callAsyncJavaScript(
            "return document.querySelector(selector).matches(':visited')",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: .page
        ) as? Bool ?? false
    }

    @MainActor
    private func renderedPixels(in webView: WKWebView) async throws -> [UInt8] {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: configuration)
        let cgImage = try XCTUnwrap(
            image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        var pixels = [UInt8](repeating: 0, count: cgImage.width * cgImage.height * 4)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: cgImage.width,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        )
        return pixels
    }

    private func pixelCount(
        near target: (red: UInt8, green: UInt8, blue: UInt8),
        in pixels: [UInt8]
    ) -> Int {
        stride(from: 0, to: pixels.count, by: 4).count { index in
            abs(Int(pixels[index]) - Int(target.red)) <= 8
                && abs(Int(pixels[index + 1]) - Int(target.green)) <= 8
                && abs(Int(pixels[index + 2]) - Int(target.blue)) <= 8
        }
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
