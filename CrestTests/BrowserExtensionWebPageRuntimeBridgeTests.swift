import JavaScriptCore
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionWebPageRuntimeBridgeTests: XCTestCase {
    private static let claudePatterns = ["https://claude.ai/*", "https://*.claude.ai/*"]
    /// Stands in for WebKit's web-page runtime: records the call and answers
    /// `{ success: true }`, or `undefined` when the message type is
    /// "unanswered" — what WebKit hands back for an unknown extension — through
    /// the callback when one is supplied and a promise otherwise.
    private static let webKitBrowser = """
        ({ runtime: {
            sendMessage: (...args) => {
                globalThis.__sent = args;
                const reply = args[1] && args[1].type === "unanswered" ? undefined : { success: true };
                const callback = args[3];
                if (typeof callback === "function") { callback(reply); return undefined; }
                return Promise.resolve(reply);
            },
            connect: (...args) => ({ connected: args })
        } })
        """

    /// Stands in for Crest's relay reply handler, which
    /// `WKScriptMessageHandlerWithReply` exposes to the page as a
    /// promise-returning `postMessage`. It records every call and answers with
    /// whatever `__relayReply` holds.
    private static let relayHandler = """
        globalThis.__relayed = [];
        globalThis.__relayReply = { relayed: true };
        globalThis.webkit = globalThis.webkit || { messageHandlers: {} };
        globalThis.webkit.messageHandlers = globalThis.webkit.messageHandlers || {};
        globalThis.webkit.messageHandlers.crestExtensionWebPageRuntimeRelay = {
            postMessage: (body) => {
                globalThis.__relayed.push(body);
                return Promise.resolve(globalThis.__relayReply);
            }
        };
        """

    private func page(
        at url: String,
        patterns: [String],
        browser: String? = BrowserExtensionWebPageRuntimeBridgeTests.webKitBrowser,
        chrome: String? = nil,
        reportsDiagnostics: Bool = false,
        relay: Bool = false,
        ancestorOrigins: [String]? = nil,
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
        // A frame inside a Crest-hosted extension document reports the panel's
        // own `chrome-extension://` origin here; the page world always has the
        // list, and this stub is the only place a bare JavaScriptCore context
        // can get one.
        if let ancestorOrigins {
            let encodedAncestors = String(
                data: try JSONSerialization.data(withJSONObject: ancestorOrigins), encoding: .utf8
            )!
            context.evaluateScript("globalThis.location.ancestorOrigins = \(encodedAncestors);")
        }
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
        if relay {
            context.evaluateScript(Self.relayHandler)
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
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "oauth_redirect" }).then((r) => { globalThis.__resolved = r; })"#
        )
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(globalThis.__sent)")!.toString(),
            #"["fcoeoab",{"type":"oauth_redirect"}]"#
        )
        XCTAssertTrue(
            context.evaluateScript("globalThis.__resolved && globalThis.__resolved.success === true")!.toBool(),
            "The promise form resolves with the extension's reply."
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

    func testAnUnansweredCallSetsLastErrorDuringTheCallbackAndRejectsThePromise() throws {
        let context = try page(at: "https://claude.ai/oauth/authorize", patterns: Self.claudePatterns)
        context.evaluateScript(
            """
            globalThis.__seen = [];
            chrome.runtime.sendMessage("dngcpim", { type: "unanswered" }, (reply) => {
                globalThis.__seen.push(reply === undefined, chrome.runtime.lastError && chrome.runtime.lastError.message);
            });
            globalThis.__seen.push(chrome.runtime.lastError === undefined);
            chrome.runtime.sendMessage("fcoeoab", { type: "ping" }, (reply) => {
                globalThis.__seen.push(reply.success === true, chrome.runtime.lastError === undefined);
            });
            """
        )
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(globalThis.__seen)")!.toString(),
            #"[true,"Could not establish connection. Receiving end does not exist.",true,true,true]"#,
            "lastError is set only while the callback of an unanswered call runs, as in Chrome."
        )
        context.evaluateScript(
            #"chrome.runtime.sendMessage("dngcpim", { type: "unanswered" }).then(() => { globalThis.__promise = "resolved"; }, (e) => { globalThis.__promise = e.message; })"#
        )
        XCTAssertEqual(
            context.evaluateScript("globalThis.__promise")!.toString(),
            "Could not establish connection. Receiving end does not exist.",
            "The promise form rejects, so a page probing several extension ids moves on to the next one."
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

    /// Inside a Crest-hosted extension document WebKit cannot route the
    /// message at all — its web-page `sendMessage` resolves the sender to a
    /// browser tab and a side panel is deliberately never one — so the alias
    /// sends through Crest's relay first and never touches WebKit.
    func testAFrameInsideAnExtensionDocumentSendsThroughTheRelayFirst() throws {
        let context = try page(
            at: "https://claude.ai/cic/new?surface=cic_sidepanel",
            patterns: Self.claudePatterns,
            relay: true,
            ancestorOrigins: ["chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn"]
        )
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "ping" }).then((r) => { globalThis.__resolved = r; })"#
        )
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(globalThis.__relayed)")!.toString(),
            #"[{"extensionId":"fcoeoab","message":{"type":"ping"}}]"#
        )
        XCTAssertEqual(
            context.evaluateScript("typeof globalThis.__sent")!.toString(), "undefined",
            "WebKit is not asked at all: it would answer undefined after a delay."
        )
        XCTAssertTrue(
            context.evaluateScript("globalThis.__resolved && globalThis.__resolved.relayed === true")!
                .toBool()
        )
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "ping" }, (reply) => { globalThis.__reply = reply; })"#
        )
        XCTAssertTrue(
            context.evaluateScript("globalThis.__reply && globalThis.__reply.relayed === true")!.toBool(),
            "The callback form is answered from the relay too."
        )
    }

    /// The relay's `null` is both its refusal and its "nobody answered", and
    /// the page must see Chrome's signal for that rather than a silent
    /// `undefined`.
    func testANullRelayAnswerBecomesLastErrorAndARejectedPromise() throws {
        let context = try page(
            at: "https://claude.ai/cic/new",
            patterns: Self.claudePatterns,
            relay: true,
            ancestorOrigins: ["chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn"]
        )
        context.evaluateScript(
            """
            globalThis.__relayReply = null;
            globalThis.__seen = [];
            chrome.runtime.sendMessage("fcoeoab", { type: "ping" }, (reply) => {
                globalThis.__seen.push(reply === undefined, chrome.runtime.lastError && chrome.runtime.lastError.message);
            });
            """
        )
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(globalThis.__seen)")!.toString(),
            #"[true,"Could not establish connection. Receiving end does not exist."]"#
        )
        XCTAssertTrue(
            context.evaluateScript("chrome.runtime.lastError === undefined")!.toBool(),
            "lastError is set only while the callback runs, as in Chrome."
        )
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "ping" }).then(() => { globalThis.__promise = "resolved"; }, (e) => { globalThis.__promise = e.message; })"#
        )
        XCTAssertEqual(
            context.evaluateScript("globalThis.__promise")!.toString(),
            "Could not establish connection. Receiving end does not exist."
        )
    }

    /// An ordinary browser tab installs no relay handler, so nothing about its
    /// round trip changes. A tab that somehow had one would still ask WebKit
    /// first, because WebKit owns the tab's sender identity.
    func testATabKeepsWebKitFirstAndFallsBackToTheRelayOnlyWhenWebKitAnswersNothing() throws {
        let context = try page(
            at: "https://claude.ai/oauth/authorize", patterns: Self.claudePatterns, relay: true
        )
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "oauth_redirect" }).then((r) => { globalThis.__resolved = r; })"#
        )
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(globalThis.__sent)")!.toString(),
            #"["fcoeoab",{"type":"oauth_redirect"}]"#,
            "WebKit is asked first outside an extension document."
        )
        XCTAssertEqual(context.evaluateScript("globalThis.__relayed.length")!.toInt32(), 0)
        XCTAssertTrue(
            context.evaluateScript("globalThis.__resolved && globalThis.__resolved.success === true")!
                .toBool()
        )

        // WebKit answers `undefined` for a message it could not route. With a
        // relay present that is a reason to try Crest, not to give up.
        context.evaluateScript(
            #"chrome.runtime.sendMessage("dngcpim", { type: "unanswered" }, (reply) => { globalThis.__reply = reply; })"#
        )
        XCTAssertEqual(
            context.evaluateScript("JSON.stringify(globalThis.__relayed)")!.toString(),
            #"[{"extensionId":"dngcpim","message":{"type":"unanswered"}}]"#
        )
        XCTAssertTrue(
            context.evaluateScript("globalThis.__reply && globalThis.__reply.relayed === true")!.toBool()
        )
    }

    /// A hosted document can frame a site while WebKit installs no web-page
    /// namespace there at all. The relay is then the only route, and the alias
    /// still has to appear.
    func testTheAliasIsInstalledOnTheRelayAloneWhenWebKitHasNoWebPageRuntime() throws {
        let context = try page(
            at: "https://claude.ai/cic/new",
            patterns: Self.claudePatterns,
            browser: nil,
            relay: true,
            ancestorOrigins: ["chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn"]
        )
        XCTAssertEqual(chromeType(in: context), "object")
        context.evaluateScript(
            #"chrome.runtime.sendMessage("fcoeoab", { type: "ping" }, (reply) => { globalThis.__reply = reply; })"#
        )
        XCTAssertTrue(
            context.evaluateScript("globalThis.__reply && globalThis.__reply.relayed === true")!.toBool()
        )
        XCTAssertTrue(
            context.evaluateScript(
                #"(() => { try { chrome.runtime.connect("fcoeoab"); return false; } catch (e) { return e.message.startsWith("Could not establish connection"); } })()"#
            )!.toBool(),
            "Crest relays one-shot messages only; a port has no route here."
        )
    }

    /// The relay does not widen the alias. A frame outside every pattern still
    /// sees no `chrome`, even inside a panel that installed the handler.
    func testTheRelayDoesNotInstallTheAliasOnAnUnmatchedFrame() throws {
        XCTAssertEqual(
            chromeType(
                in: try page(
                    at: "https://example.com/", patterns: Self.claudePatterns, relay: true,
                    ancestorOrigins: ["chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn"])
            ),
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
