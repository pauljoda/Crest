import JavaScriptCore
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebPageRuntimeBridgeTests: XCTestCase {
    private static let claudePatterns = ["https://claude.ai/*", "https://*.claude.ai/*"]
    private static let webKitBrowser = """
        ({ runtime: {
            sendMessage: (...args) => { globalThis.__sent = args; return "reply"; },
            connect: (...args) => ({ connected: args })
        } })
        """

    private func page(
        at url: String,
        patterns: [String],
        browser: String? = BrowserExtensionWebPageRuntimeBridgeTests.webKitBrowser,
        chrome: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        var thrown: String?
        context.exceptionHandler = { _, exception in
            thrown = exception?.toString()
        }
        let encodedURL = String(
            data: try JSONSerialization.data(withJSONObject: [url]), encoding: .utf8
        )!
        context.evaluateScript("globalThis.location = { href: \(encodedURL)[0] };")
        if let browser {
            context.evaluateScript("globalThis.browser = \(browser);")
        }
        if let chrome {
            context.evaluateScript("globalThis.chrome = \(chrome);")
        }
        context.evaluateScript(
            BrowserExtensionWebPageRuntimeBridge.source(matchPatterns: patterns)
        )
        XCTAssertNil(thrown, "The alias script must not throw", file: file, line: line)
        return context
    }

    private func chromeType(in context: JSContext) -> String {
        context.evaluateScript("typeof globalThis.chrome")!.toString()
    }

    func testAMatchingPageGainsChromeRuntimeThatForwardsToWebKitsBrowserRuntime() throws {
        let context = try page(
            at: "https://claude.ai/oauth/authorize?client_id=x&redirect_uri=y",
            patterns: Self.claudePatterns
        )
        XCTAssertEqual(
            context.evaluateScript("typeof chrome.runtime.sendMessage")!.toString(), "function"
        )
        XCTAssertEqual(
            context.evaluateScript(
                #"chrome.runtime.sendMessage("fcoeoab", { type: "oauth_redirect" })"#
            )!.toString(),
            "reply"
        )
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(globalThis.__sent)")!.toString(),
            #"["fcoeoab",{"type":"oauth_redirect"}]"#
        )
        XCTAssertEqual(
            context.evaluateScript(#"chrome.runtime.connect("fcoeoab", { name: "p" }).connected[1].name"#)!
                .toString(),
            "p"
        )
        XCTAssertTrue(
            context.evaluateScript("chrome.runtime.id === undefined")!.toBool(),
            "Chrome leaves runtime.id undefined on web pages."
        )
    }

    func testASubdomainWildcardCoversTheApexAndItsSubdomainsOnly() throws {
        XCTAssertEqual(
            chromeType(in: try page(at: "https://www.claude.ai/chrome/installed", patterns: Self.claudePatterns)),
            "object"
        )
        XCTAssertEqual(
            chromeType(in: try page(at: "https://claude.ai/", patterns: ["https://*.claude.ai/*"])),
            "object"
        )
        XCTAssertEqual(
            chromeType(in: try page(at: "https://notclaude.ai/", patterns: Self.claudePatterns)),
            "undefined"
        )
    }

    func testPagesOutsideEveryPatternKeepChromeUndefined() throws {
        XCTAssertEqual(
            chromeType(in: try page(at: "https://example.com/", patterns: Self.claudePatterns)),
            "undefined",
            "Ordinary sites must never see a chrome object and mistake Crest for Chrome."
        )
    }

    func testSchemeAndPathParticipateInTheMatch() throws {
        XCTAssertEqual(
            chromeType(in: try page(at: "http://claude.ai/", patterns: ["https://claude.ai/*"])),
            "undefined"
        )
        XCTAssertEqual(
            chromeType(in: try page(at: "http://claude.ai/oauth/x", patterns: ["*://claude.ai/oauth/*"])),
            "object"
        )
        XCTAssertEqual(
            chromeType(in: try page(at: "https://claude.ai/app", patterns: ["https://claude.ai/oauth/*"])),
            "undefined"
        )
        XCTAssertEqual(
            chromeType(
                in: try page(at: "https://claude.ai/oauth/authorize?state=1", patterns: ["https://claude.ai/oauth/*"])
            ),
            "object",
            "Chrome matches the path glob against the path and query together."
        )
    }

    func testAllURLsCoversWebSchemesOnly() throws {
        XCTAssertEqual(
            chromeType(in: try page(at: "https://example.org/", patterns: ["<all_urls>"])),
            "object"
        )
        XCTAssertEqual(
            chromeType(in: try page(at: "about:blank", patterns: ["<all_urls>"])),
            "undefined"
        )
    }

    func testAnExistingChromeObjectIsLeftAlone() throws {
        let context = try page(
            at: "https://claude.ai/", patterns: Self.claudePatterns, chrome: "({ webstore: 1 })"
        )
        XCTAssertEqual(context.evaluateScript("chrome.webstore")!.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("typeof chrome.runtime")!.toString(), "undefined")
    }

    func testWithoutWebKitsBrowserRuntimeNothingIsInstalled() throws {
        XCTAssertEqual(
            chromeType(in: try page(at: "https://claude.ai/", patterns: Self.claudePatterns, browser: nil)),
            "undefined"
        )
        XCTAssertEqual(
            chromeType(in: try page(at: "https://claude.ai/", patterns: Self.claudePatterns, browser: "({})")),
            "undefined"
        )
    }

    func testInstallAddsOneDocumentStartPageWorldScriptOnlyWhenPatternsExist() {
        let empty = WKUserContentController()
        BrowserExtensionWebPageRuntimeBridge.install(in: empty, matchPatterns: [])
        XCTAssertTrue(empty.userScripts.isEmpty)

        let controller = WKUserContentController()
        BrowserExtensionWebPageRuntimeBridge.install(
            in: controller, matchPatterns: Self.claudePatterns
        )
        XCTAssertEqual(controller.userScripts.count, 1)
        let script = controller.userScripts[0]
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertFalse(script.isForMainFrameOnly)
        XCTAssertTrue(
            script.source.contains(#"["https:\/\/claude.ai\/*","https:\/\/*.claude.ai\/*"]"#)
                || script.source.contains(#"["https://claude.ai/*","https://*.claude.ai/*"]"#),
            "The authored patterns are embedded as JSON."
        )
        XCTAssertFalse(script.source.contains(BrowserExtensionWebPageRuntimeBridge.patternsPlaceholder))
    }
}
