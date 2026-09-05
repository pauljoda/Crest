import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerPageTests: XCTestCase {
    func testLifecycleEventsCarryTheNavigatedLoaderAndStopWhenDisabled() async throws {
        try await withPage { page, fixture, _ in
            _ = try await page.execute("Page.setLifecycleEventsEnabled", parameters: ["enabled": true])
            let destination = try fixture.writePage(
                named: "lifecycle.html", html: "<!doctype html><title>Lifecycle</title>")
            _ = try await page.execute("Page.navigate", parameters: ["url": destination.absoluteString])
            try await fixture.waitForEvent("Page.lifecycleEvent") { $0["name"] as? String == "load" }
            let navigated = try XCTUnwrap(fixture.all("Page.frameNavigated").last?["frame"] as? [String: Any])
            for event in fixture.all("Page.lifecycleEvent") {
                XCTAssertEqual(event["frameId"] as? String, navigated["id"] as? String)
                XCTAssertEqual(event["loaderId"] as? String, navigated["loaderId"] as? String)
                XCTAssertNotNil(event["timestamp"] as? Double)
            }
            XCTAssertTrue(fixture.all("Page.lifecycleEvent").contains { $0["name"] as? String == "DOMContentLoaded" })
            let count = fixture.all("Page.lifecycleEvent").count
            let loads = fixture.all("Page.loadEventFired").count
            _ = try await page.execute("Page.setLifecycleEventsEnabled", parameters: ["enabled": false])
            _ = try await page.execute("Page.reload", parameters: [:])
            try await BrowserChromeDebuggerDomainFixture.waitFor { fixture.all("Page.loadEventFired").count > loads }
            XCTAssertEqual(fixture.all("Page.lifecycleEvent").count, count)
        }
    }

    func testLayoutMetricsMeasureScrolledContentWithoutMovingThePage() async throws {
        try await withPage { page, fixture, _ in
            _ = try await fixture.page.evaluateJavaScript(
                """
                document.documentElement.style.cssText = 'overflow:scroll; scrollbar-width:none';
                document.body.style.cssText = 'margin:0; width:1600px; height:2400px';
                window.scrollTo(120, 300);
                undefined
                """)
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 5) {
                (try? await fixture.page.evaluateJavaScript("scrollY")) as? Int == 300
            }
            let result = try await page.execute("Page.getLayoutMetrics", parameters: [:])
            let layout = try XCTUnwrap(result["cssLayoutViewport"] as? [String: Double])
            XCTAssertEqual(layout, ["pageX": 120, "pageY": 300, "clientWidth": 640, "clientHeight": 480])
            XCTAssertEqual(
                result["cssContentSize"] as? [String: Double], ["x": 0, "y": 0, "width": 1600, "height": 2400])
            let visual = try XCTUnwrap(result["cssVisualViewport"] as? [String: Double])
            XCTAssertEqual(visual["pageY"], 300)
            XCTAssertEqual(visual["clientWidth"], 640)
            XCTAssertEqual(visual["scale"], 1)
            let measuredRatio = try await fixture.page.evaluateJavaScript("devicePixelRatio")
            let ratio = try XCTUnwrap(measuredRatio as? Double)
            let legacy = try XCTUnwrap(result["layoutViewport"] as? [String: Double])
            XCTAssertEqual(legacy["clientWidth"], 640 * ratio)
            XCTAssertEqual(legacy["pageY"], 300 * ratio)
            let scrollY = try await fixture.page.evaluateJavaScript("scrollY")
            XCTAssertEqual(scrollY as? Int, 300)
        }
    }

    func testLayoutMetricsRespectPageZoomAndIgnorePageDefinedGetters() async throws {
        try await withPage { page, fixture, _ in
            fixture.page.pageZoom = 2
            _ = try await fixture.page.evaluateJavaScript(
                """
                document.documentElement.style.cssText = 'scrollbar-width:none';
                document.body.style.cssText = 'margin:0; height:1000px';
                Object.defineProperty(window, 'visualViewport', { get() { throw new Error('page getter'); } });
                Object.defineProperty(window, 'devicePixelRatio', { get() { return 9000; } });
                undefined
                """)
            let result = try await page.execute("Page.getLayoutMetrics", parameters: [:])
            let layout = try XCTUnwrap(result["cssLayoutViewport"] as? [String: Double])
            XCTAssertEqual(layout["clientWidth"], 320)
            XCTAssertEqual(layout["clientHeight"], 240)
            let visual = try XCTUnwrap(result["cssVisualViewport"] as? [String: Double])
            XCTAssertEqual(visual["zoom"], 2)
            let legacy = try XCTUnwrap(result["layoutViewport"] as? [String: Double])
            XCTAssertLessThan(try XCTUnwrap(legacy["clientWidth"]), 10000)
        }
    }

    func testFrameTreeAndNavigationReportTheSameChromeFrame() async throws {
        try await withPage { page, fixture, _ in
            let tree = try await page.execute("Page.getFrameTree", parameters: [:])
            let frame = try XCTUnwrap((tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any])
            let frameID = try XCTUnwrap(frame["id"] as? String)
            XCTAssertFalse(frameID.isEmpty)
            XCTAssertNil(frame["parentId"])
            let loaderID = try XCTUnwrap(frame["loaderId"] as? String)
            XCTAssertFalse(loaderID.isEmpty)
            XCTAssertTrue(try XCTUnwrap(frame["url"] as? String).hasSuffix("start.html"))
            XCTAssertNotNil(frame["securityOrigin"] as? String)
            XCTAssertEqual(frame["mimeType"] as? String, "text/html")
            XCTAssertEqual(frame["secureContextType"] as? String, "Secure")
            XCTAssertEqual(frame["crossOriginIsolatedContextType"] as? String, "NotIsolated")
            XCTAssertNotNil(frame["gatedAPIFeatures"] as? [Any])
            XCTAssertNil((tree["frameTree"] as? [String: Any])?["resources"])

            let second = try fixture.writePage(
                named: "second.html", html: "<!doctype html><title>Crest second document</title>")
            let response = try await page.execute("Page.navigate", parameters: ["url": second.absoluteString])
            XCTAssertEqual(response["frameId"] as? String, frameID)
            XCTAssertNotEqual(
                response["loaderId"] as? String, loaderID,
                "Navigating starts a new document, and Chrome answers with that document's loader.")
            try await fixture.waitForEvent("Page.frameNavigated") { parameters in
                ((parameters["frame"] as? [String: Any])?["url"] as? String)?.hasSuffix("second.html") == true
            }
            let navigated = try XCTUnwrap(
                fixture.all("Page.frameNavigated").last {
                    (($0["frame"] as? [String: Any])?["url"] as? String)?.hasSuffix("second.html") == true
                })
            XCTAssertEqual(navigated["type"] as? String, "Navigation")
            let navigatedFrame = try XCTUnwrap(navigated["frame"] as? [String: Any])
            XCTAssertEqual(navigatedFrame["id"] as? String, frameID)
            XCTAssertNotEqual(navigatedFrame["loaderId"] as? String, loaderID)
            XCTAssertEqual(navigatedFrame["domainAndRegistry"] as? String, "")
            XCTAssertNil(navigatedFrame["parentId"])
        }
    }

    func testAChildFrameAppearsUnderItsParentInTheFrameTree() async throws {
        try await withPage { page, fixture, _ in
            _ = try await fixture.page.evaluateJavaScript(
                """
                globalThis.crestChildLoaded = false;
                const frame = document.createElement('iframe');
                frame.onload = () => { crestChildLoaded = true; };
                frame.srcdoc = '<!doctype html><title>Child frame</title>';
                document.body.append(frame);
                undefined
                """)
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                (try? await fixture.page.evaluateJavaScript("globalThis.crestChildLoaded")) as? Bool == true
            }
            let tree = try await page.execute("Page.getFrameTree", parameters: [:])
            let root = try XCTUnwrap(tree["frameTree"] as? [String: Any])
            let children = try XCTUnwrap(root["childFrames"] as? [[String: Any]])
            let child = try XCTUnwrap(children.first?["frame"] as? [String: Any])
            XCTAssertEqual(
                child["parentId"] as? String, (root["frame"] as? [String: Any])?["id"] as? String)
            XCTAssertFalse(try XCTUnwrap(child["id"] as? String).isEmpty)
        }
    }

    func testAlertIsHeldForTheClientAndReleasedByHandleJavaScriptDialog() async throws {
        let host = BrowserChromeDebuggerDialogPage()
        try await withPage(uiDelegate: host) { page, fixture, _ in
            let answered = self.expectation(description: "Page resumed after the dialog was accepted")
            fixture.page.evaluateJavaScript("alert('crest-alert'); 'resumed'") { value, _ in
                XCTAssertEqual(value as? String, "resumed")
                answered.fulfill()
            }
            try await fixture.waitForEvent("Page.javascriptDialogOpening")
            let opening = try XCTUnwrap(fixture.first("Page.javascriptDialogOpening"))
            XCTAssertEqual(opening["message"] as? String, "crest-alert")
            XCTAssertEqual(opening["type"] as? String, "alert")
            XCTAssertEqual(opening["hasBrowserHandler"] as? Bool, true)
            XCTAssertFalse(try XCTUnwrap(opening["frameId"] as? String).isEmpty)
            XCTAssertTrue(try XCTUnwrap(opening["url"] as? String).hasSuffix("start.html"))
            XCTAssertTrue(host.presentedByCrest.isEmpty, "An intercepted dialog must not also reach the user.")

            _ = try await page.execute("Page.handleJavaScriptDialog", parameters: ["accept": true])
            await self.fulfillment(of: [answered], timeout: 5)
            let closed = try XCTUnwrap(fixture.first("Page.javascriptDialogClosed"))
            XCTAssertEqual(closed["result"] as? Bool, true)
        }
    }

    func testPromptCarriesItsDefaultAndReturnsTheClientsText() async throws {
        let host = BrowserChromeDebuggerDialogPage()
        try await withPage(uiDelegate: host) { page, fixture, _ in
            let answered = self.expectation(description: "Prompt resolved with the client's text")
            fixture.page.evaluateJavaScript("prompt('crest-prompt', 'preset')") { value, _ in
                XCTAssertEqual(value as? String, "crest-answer")
                answered.fulfill()
            }
            try await fixture.waitForEvent("Page.javascriptDialogOpening")
            let opening = try XCTUnwrap(fixture.first("Page.javascriptDialogOpening"))
            XCTAssertEqual(opening["type"] as? String, "prompt")
            XCTAssertEqual(opening["defaultPrompt"] as? String, "preset")
            _ = try await page.execute(
                "Page.handleJavaScriptDialog", parameters: ["accept": true, "promptText": "crest-answer"])
            await self.fulfillment(of: [answered], timeout: 5)
            XCTAssertEqual(fixture.first("Page.javascriptDialogClosed")?["userInput"] as? String, "crest-answer")
        }
    }

    func testDetachDismissesAWaitingDialogInsteadOfLeavingThePageBlocked() async throws {
        let host = BrowserChromeDebuggerDialogPage()
        try await withPage(uiDelegate: host) { page, fixture, _ in
            let answered = self.expectation(description: "Confirm rejected when the session ended")
            fixture.page.evaluateJavaScript("confirm('crest-confirm')") { value, _ in
                XCTAssertEqual(value as? Bool, false)
                answered.fulfill()
            }
            try await fixture.waitForEvent("Page.javascriptDialogOpening")
            page.detach()
            await self.fulfillment(of: [answered], timeout: 5)
            XCTAssertEqual(fixture.first("Page.javascriptDialogClosed")?["result"] as? Bool, false)
            XCTAssertNil(host.debuggerDialogInterceptor, "Detaching must return dialogs to the user.")
        }
    }

    func testDisabledPageDomainReturnsDialogsToTheUser() async throws {
        let host = BrowserChromeDebuggerDialogPage()
        try await withPage(uiDelegate: host) { page, fixture, _ in
            _ = try await page.execute("Page.disable", parameters: [:])
            let presented = self.expectation(description: "Crest presented the dialog itself")
            fixture.page.evaluateJavaScript("alert('crest-user-dialog'); 'resumed'") { _, _ in presented.fulfill() }
            await self.fulfillment(of: [presented], timeout: 5)
            XCTAssertEqual(host.presentedByCrest, ["crest-user-dialog"])
            XCTAssertTrue(fixture.all("Page.javascriptDialogOpening").isEmpty)
        }
    }

    func testTabOperationsRouteOutOfTheProtocolAndScriptNavigationIsRefused() async throws {
        try await withPage { page, fixture, host in
            _ = try await page.execute("Page.bringToFront", parameters: [:])
            XCTAssertEqual(host.activated, [fixture.target])
            _ = try await page.execute("Page.close", parameters: [:])
            XCTAssertEqual(host.closed, [fixture.target])
            do {
                _ = try await page.execute("Page.navigate", parameters: ["url": "javascript:globalThis.crest = 1"])
                XCTFail("Navigating to script must not run page code outside evaluation's constraints.")
            } catch BrowserChromeDebuggerProtocolError.unsupportedParameter("url") {}
            do {
                _ = try await page.execute("Page.setDownloadBehavior", parameters: [:])
                XCTFail("An unimplemented Page command must report unsupported.")
            } catch BrowserChromeDebuggerProtocolError.unsupportedCommand {}
        }
    }

    func testReloadRunsThePageAgainAndRejectsUnsupportedOptions() async throws {
        try await withPage { page, fixture, _ in
            _ = try await fixture.page.evaluateJavaScript("globalThis.crestSurvivesReload = true; undefined")
            _ = try await page.execute("Page.reload", parameters: ["ignoreCache": true])
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                (try? await fixture.page.evaluateJavaScript("typeof globalThis.crestSurvivesReload")) as? String
                    == "undefined"
            }
            do {
                _ = try await page.execute("Page.reload", parameters: ["scriptToEvaluateOnLoad": "globalThis.x = 1"])
                XCTFail("An unsupported reload option must not be silently dropped.")
            } catch BrowserChromeDebuggerProtocolError.unsupportedParameter("scriptToEvaluateOnLoad") {}
        }
    }

    private func withPage(
        uiDelegate: (any WKUIDelegate)? = nil,
        _ operation: (
            BrowserChromeDebuggerPage, BrowserChromeDebuggerDomainFixture, BrowserChromeDebuggerTabHostDouble
        ) async throws -> Void
    ) async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(
            navigable: true, uiDelegate: uiDelegate)
        defer { fixture.tearDown() }
        let host = BrowserChromeDebuggerTabHostDouble()
        let page = BrowserChromeDebuggerPage(
            connection: fixture.connection, target: fixture.target, webView: fixture.page, tabHost: host)
        page.onEvent = fixture.recorder()
        fixture.route([{ [weak page] method, parameters in page?.receive(method, parameters: parameters) }])
        _ = try await page.execute("Page.enable", parameters: [:])
        defer { page.detach() }
        try await operation(page, fixture, host)
    }
}
