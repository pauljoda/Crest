import JavaScriptCore
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebPageRuntimeBridgeTests: XCTestCase {
    private static let claudePatterns = ["https://claude.ai/*", "https://*.claude.ai/*"]
    /// Stands in for WebKit's web-page runtime: records the call, answers a
    /// supplied callback the way WebKit does, and returns "reply" otherwise.
    private static let webKitBrowser = """
        ({ runtime: {
            sendMessage: (...args) => {
                globalThis.__sent = args;
                const callback = args[3];
                if (typeof callback === "function") { callback({ success: true }); return undefined; }
                return "reply";
            },
            connect: (...args) => ({ connected: args })
        } })
        """

    private func page(
        at url: String,
        patterns: [String],
        browser: String? = BrowserExtensionWebPageRuntimeBridgeTests.webKitBrowser,
        chrome: String? = nil,
        reportsDiagnostics: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        var thrown: String?
        context.exceptionHandler = { _, exception in
            thrown = exception?.toString()
        }
        // Bare JavaScriptCore has no `URL`; the page world's `location`
        // fields are what the script reads, so supply those.
        let components = try XCTUnwrap(URLComponents(string: url))
        let location: [String: String] = [
            "href": url,
            "protocol": (components.scheme ?? "") + ":",
            "hostname": components.host ?? "",
            "pathname": components.path.isEmpty ? "/" : components.path,
            "search": components.query.map { "?" + $0 } ?? "",
        ]
        let encodedLocation = String(
            data: try JSONSerialization.data(withJSONObject: location), encoding: .utf8
        )!
        context.evaluateScript("globalThis.location = \(encodedLocation);")
        if let browser {
            context.evaluateScript("globalThis.browser = \(browser);")
        }
        if let chrome {
            context.evaluateScript("globalThis.chrome = \(chrome);")
        }
        if reportsDiagnostics {
            context.evaluateScript(
                """
                globalThis.__reports = [];
                globalThis.webkit = { messageHandlers: { crestExtensionWebPageRuntime: {
                    postMessage: (body) => { globalThis.__reports.push(body); } } } };
                """
            )
        }
        context.evaluateScript(
            BrowserExtensionWebPageRuntimeBridge.source(
                matchPatterns: patterns, reportsDiagnostics: reportsDiagnostics
            )
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

    func testACallbackInTheOptionsSlotIsForwardedAsTheCallback() throws {
        let context = try page(at: "https://claude.ai/oauth/authorize", patterns: Self.claudePatterns)
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "ping" }, (reply) => { globalThis.__reply = reply; })"#
        )
        XCTAssertEqual(
            context.evaluateScript("globalThis.__sent.length")!.toInt32(), 4,
            "The callback travels in WebKit's fourth position with options left undefined."
        )
        XCTAssertTrue(context.evaluateScript("globalThis.__sent[2] === undefined")!.toBool())
        XCTAssertEqual(context.evaluateScript("typeof globalThis.__sent[3]")!.toString(), "function")
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "ping" }, { includeTlsChannelId: true }, () => {})"#
        )
        XCTAssertTrue(context.evaluateScript("globalThis.__sent[2].includeTlsChannelId === true")!.toBool())
        XCTAssertEqual(context.evaluateScript("typeof globalThis.__sent[3]")!.toString(), "function")
        context.evaluateScript(#"chrome.runtime.sendMessage("fcoeoab", { type: "ping" })"#)
        XCTAssertEqual(
            context.evaluateScript("globalThis.__sent.length")!.toInt32(), 2,
            "Without a callback or options the promise form reaches WebKit with just the two arguments."
        )
    }

    func testDiagnosticsReportShapesAndOutcomesWithoutPayloadValues() throws {
        let context = try page(
            at: "https://claude.ai/oauth/authorize", patterns: Self.claudePatterns, reportsDiagnostics: true
        )
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "oauth_redirect", redirect_uri: "secret" }, () => {})"#
        )
        context.evaluateScript(#"chrome.runtime.sendMessage("fcoeoab", { type: "ping" })"#)
        let reports = context.evaluateScript("JSON.stringify(globalThis.__reports)")!.toString()!
        XCTAssertTrue(reports.contains(#""event":"sendMessage""#))
        XCTAssertTrue(reports.contains(#""type":"oauth_redirect""#))
        XCTAssertTrue(reports.contains(#""form":"callback""#))
        XCTAssertTrue(reports.contains(#""form":"promise""#))
        XCTAssertTrue(reports.contains(#""keys":["type","redirect_uri"]"#))
        XCTAssertFalse(reports.contains("secret"), "Diagnostics carry shapes, never payload values.")
        // The fake WebKit runtime replies synchronously through the callback.
        XCTAssertTrue(reports.contains(#""outcome":"replied""#))
    }

    func testDiagnosticsStayOutOfTheScriptWhenNotRequested() throws {
        let context = try page(at: "https://claude.ai/", patterns: Self.claudePatterns)
        XCTAssertFalse(
            BrowserExtensionWebPageRuntimeBridge.source(matchPatterns: Self.claudePatterns)
                .contains(BrowserExtensionWebPageRuntimeBridge.diagnosticsPlaceholder)
        )
        XCTAssertEqual(context.evaluateScript("typeof globalThis.__reports")!.toString(), "undefined")
        XCTAssertEqual(context.evaluateScript("typeof chrome.runtime.sendMessage")!.toString(), "function")
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
        XCTAssertTrue(script.source.contains("const reportsDiagnostics = false;"))

        let reporting = WKUserContentController()
        let proxy = BrowserExtensionWebPageRuntimeBridge.install(
            in: reporting, matchPatterns: Self.claudePatterns, reportsDiagnostics: true
        )
        XCTAssertNotNil(proxy, "Diagnostics hand back the handler the page must remove on teardown.")
        XCTAssertTrue(reporting.userScripts[0].source.contains("const reportsDiagnostics = true;"))
    }
}
