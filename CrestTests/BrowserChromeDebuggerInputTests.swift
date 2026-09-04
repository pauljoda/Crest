import AppKit
import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserChromeDebuggerInputTests: XCTestCase {
    private static let markup = """
        <!doctype html><title>Crest input test</title>
        <style>
            body { margin: 0; font: 16px system-ui; }
            #button { position: absolute; left: 20px; top: 20px; width: 200px; height: 60px; }
            #field { position: absolute; left: 20px; top: 120px; width: 300px; height: 40px; }
            #filler { position: absolute; top: 2000px; height: 2000px; width: 10px; }
        </style>
        <button id="button" onclick="this.textContent = 'clicked'">idle</button>
        <input id="field" value="">
        <div id="filler"></div>
        """

    func testClickTogglesTheButtonUnderTheGivenCssPixel() async throws {
        try await withInput { input, fixture in
            for type in ["mousePressed", "mouseReleased"] {
                _ = try await input.execute(
                    "Input.dispatchMouseEvent",
                    parameters: [
                        "type": type, "x": 120, "y": 50, "button": "left", "clickCount": 1,
                    ])
            }
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                (try? await fixture.page.evaluateJavaScript("document.getElementById('button').textContent"))
                    as? String == "clicked"
            }
        }
    }

    func testTypingFillsTheFocusedFieldAndEnterSubmitsIt() async throws {
        try await withInput { input, fixture in
            _ = try await fixture.page.evaluateJavaScript(
                """
                const field = document.getElementById('field');
                field.focus();
                globalThis.crestKeys = [];
                field.addEventListener('keydown', event => crestKeys.push(event.key));
                undefined
                """)
            for (key, code) in [("h", "KeyH"), ("i", "KeyI")] {
                for type in ["keyDown", "keyUp"] {
                    _ = try await input.execute(
                        "Input.dispatchKeyEvent",
                        parameters: ["type": type, "key": key, "code": code, "text": key])
                }
            }
            _ = try await input.execute(
                "Input.dispatchKeyEvent", parameters: ["type": "rawKeyDown", "key": "Enter", "code": "Enter"])
            _ = try await input.execute(
                "Input.dispatchKeyEvent", parameters: ["type": "keyUp", "key": "Enter", "code": "Enter"])
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                (try? await fixture.page.evaluateJavaScript("document.getElementById('field').value")) as? String
                    == "hi"
            }
            let keys = try await fixture.page.evaluateJavaScript("crestKeys.join(',')") as? String
            XCTAssertEqual(keys, "h,i,Enter")
        }
    }

    func testInsertTextPlacesWholeTextInTheFocusedField() async throws {
        try await withInput { input, fixture in
            _ = try await fixture.page.evaluateJavaScript("document.getElementById('field').focus(); undefined")
            _ = try await input.execute("Input.insertText", parameters: ["text": "crest inserted"])
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                (try? await fixture.page.evaluateJavaScript("document.getElementById('field').value")) as? String
                    == "crest inserted"
            }
        }
    }

    func testWheelScrollsThePageDown() async throws {
        try await withInput { input, fixture in
            _ = try await input.execute(
                "Input.dispatchMouseEvent",
                parameters: [
                    "type": "mouseWheel", "x": 300, "y": 300, "button": "none", "deltaX": 0, "deltaY": 400,
                ])
            try await BrowserChromeDebuggerDomainFixture.waitFor(seconds: 10) {
                let offset = (try? await fixture.page.evaluateJavaScript("window.scrollY")) as? Double ?? 0
                return offset > 0
            }
        }
    }

    func testInvalidInputParametersRejectBeforeReachingThePage() async throws {
        try await withInput { input, fixture in
            for parameters in [
                ["type": "mousePressed", "x": 10, "y": 10, "button": "sideways"] as [String: Any],
                ["type": "hovered", "x": 10, "y": 10] as [String: Any],
                ["type": "mousePressed", "x": 10, "y": 10, "modifiers": 99] as [String: Any],
            ] {
                do {
                    _ = try await input.execute("Input.dispatchMouseEvent", parameters: parameters)
                    XCTFail("An invalid mouse event must not be delivered: \(parameters)")
                } catch is BrowserChromeDebuggerProtocolError {}
            }
            do {
                _ = try await input.execute(
                    "Input.dispatchKeyEvent", parameters: ["type": "keyDown", "code": "NoSuchKey"])
                XCTFail("A key Crest cannot name must not become a silent no-op.")
            } catch BrowserChromeDebuggerProtocolError.unsupportedParameter("code") {}
            let text = try await fixture.page.evaluateJavaScript("document.getElementById('button').textContent")
            XCTAssertEqual(text as? String, "idle")
        }
    }

    func testModifierBitsBecomeRealModifierFlags() throws {
        XCTAssertEqual(try BrowserChromeDebuggerKeyCodes.modifierFlags(nil), [])
        XCTAssertEqual(try BrowserChromeDebuggerKeyCodes.modifierFlags(1), .option)
        XCTAssertEqual(try BrowserChromeDebuggerKeyCodes.modifierFlags(2), .control)
        XCTAssertEqual(try BrowserChromeDebuggerKeyCodes.modifierFlags(4), .command)
        XCTAssertEqual(try BrowserChromeDebuggerKeyCodes.modifierFlags(8), .shift)
        XCTAssertEqual(try BrowserChromeDebuggerKeyCodes.modifierFlags(12), [.command, .shift])
        XCTAssertThrowsError(try BrowserChromeDebuggerKeyCodes.modifierFlags(16))
    }

    private func withInput(
        _ operation: (BrowserChromeDebuggerInput, BrowserChromeDebuggerDomainFixture) async throws -> Void
    ) async throws {
        let fixture = try await BrowserChromeDebuggerDomainFixture.make(html: Self.markup, hosted: true)
        defer { fixture.tearDown() }
        try await operation(BrowserChromeDebuggerInput(webView: fixture.page), fixture)
    }
}
