import XCTest

@testable import Crest

/// Chrome's match-pattern grammar as Crest evaluates it in Swift. The
/// page-world alias carries the same grammar in JavaScript
/// (`BrowserExtensionWebPageRuntimeBridgeTests` pins that half); this is the
/// copy the relay checks a sending frame against, and the two must agree.
final class BrowserExtensionMatchPatternPolicyTests: XCTestCase {
    private func matches(_ url: String, _ patterns: [String]) throws -> Bool {
        BrowserExtensionMatchPatternPolicy.matches(
            url: try XCTUnwrap(URL(string: url)), anyOf: patterns)
    }

    func testHostAndSchemeWildcards() throws {
        XCTAssertTrue(try matches("https://claude.ai/cic/new", ["https://claude.ai/*"]))
        XCTAssertFalse(try matches("http://claude.ai/cic/new", ["https://claude.ai/*"]))
        XCTAssertTrue(try matches("http://claude.ai/cic/new", ["*://claude.ai/*"]))
        XCTAssertTrue(try matches("https://claude.ai/x", ["*://claude.ai/*"]))
        // A `*` scheme is http or https only, never ws or file.
        XCTAssertFalse(try matches("ws://claude.ai/socket", ["*://claude.ai/*"]))
        XCTAssertTrue(try matches("ws://claude.ai/socket", ["ws://claude.ai/*"]))
        XCTAssertTrue(try matches("https://anything.test/x", ["https://*/*"]))
    }

    func testSubdomainWildcardCoversTheApexAndItsSubdomainsOnly() throws {
        XCTAssertTrue(try matches("https://claude.ai/", ["https://*.claude.ai/*"]))
        XCTAssertTrue(try matches("https://www.claude.ai/", ["https://*.claude.ai/*"]))
        XCTAssertTrue(try matches("https://a.b.claude.ai/", ["https://*.claude.ai/*"]))
        XCTAssertFalse(
            try matches("https://notclaude.ai/", ["https://*.claude.ai/*"]),
            "A host that merely ends with those characters is a different site.")
        XCTAssertFalse(try matches("https://claude.ai.evil.test/", ["https://*.claude.ai/*"]))
    }

    /// Chrome matches the path glob against the path and the query together,
    /// which is what an OAuth hand-back URL depends on.
    func testThePathGlobCoversThePathAndQuery() throws {
        XCTAssertTrue(try matches("https://claude.ai/oauth/authorize", ["https://claude.ai/oauth/*"]))
        XCTAssertFalse(try matches("https://claude.ai/app", ["https://claude.ai/oauth/*"]))
        XCTAssertTrue(
            try matches("https://claude.ai/cic/new?surface=cic_sidepanel", ["https://claude.ai/*"]))
        XCTAssertTrue(
            try matches("https://claude.ai/x?code=abc", ["https://claude.ai/*code=*"]),
            "The query participates in the glob.")
        XCTAssertTrue(try matches("https://claude.ai/", ["https://claude.ai/"]))
        XCTAssertFalse(try matches("https://claude.ai/x", ["https://claude.ai/"]))
    }

    func testAllURLsCoversTheWebSchemesChromeListsForIt() throws {
        for url in [
            "https://example.test/", "http://example.test/", "ws://example.test/",
            "wss://example.test/", "ftp://example.test/", "file:///tmp/x",
        ] {
            XCTAssertTrue(try matches(url, ["<all_urls>"]), url)
        }
        XCTAssertFalse(try matches("about:blank", ["<all_urls>"]))
        XCTAssertFalse(try matches("chrome-extension://abc/sidepanel.html", ["<all_urls>"]))
    }

    func testMalformedPatternsMatchNothing() throws {
        XCTAssertFalse(try matches("https://claude.ai/", [""]))
        XCTAssertFalse(try matches("https://claude.ai/", ["claude.ai"]))
        XCTAssertFalse(try matches("https://claude.ai/", ["https://claude.ai"]))
        XCTAssertFalse(
            try matches("https://claude.ai/", ["https://cla*de.ai/*"]),
            "A `*` anywhere but a leading `*.` is not a legal host.")
        XCTAssertFalse(try matches("https://claude.ai/", ["chrome-extension://claude.ai/*"]))
        XCTAssertFalse(try matches("https://claude.ai/", []))
    }

    func testAnyOfIsSatisfiedByOnePattern() throws {
        let patterns = ["https://example.test/*", "https://*.claude.ai/*"]
        XCTAssertTrue(try matches("https://www.claude.ai/x", patterns))
        XCTAssertFalse(try matches("https://elsewhere.test/x", patterns))
    }
}
