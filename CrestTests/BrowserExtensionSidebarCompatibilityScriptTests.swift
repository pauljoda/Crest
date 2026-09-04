import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionSidebarCompatibilityScriptTests: XCTestCase {
    func testFullSurfaceIDsCallbacksAndGestureCapture() async throws {
        let result = try await evaluate(
            """
            const surface = Object.keys(sidePanel).sort();
            const firefoxSurface = Object.keys(sidebarAction).sort();
            await sidePanel.setOptions({tabId: 7, enabled: false});
            const options = await sidePanel.getOptions({tabId: 7});
            const callbackLayout = await new Promise(resolve => sidePanel.getLayout(resolve));
            activation = true;
            const opening = sidePanel.open({tabId: 7, windowId: 12});
            activation = false;
            await opening;
            await sidebarAction.setTitle({title: null, windowId: -2});
            return {surface, firefoxSurface, requests, options, callbackLayout};
            """)
        XCTAssertEqual(
            result["surface"] as? [String],
            [
                "Side", "close", "getLayout", "getOptions", "getPanelBehavior", "onClosed", "onOpened", "open",
                "setOptions", "setPanelBehavior",
            ])
        XCTAssertEqual(
            result["firefoxSurface"] as? [String],
            ["close", "getPanel", "getTitle", "isOpen", "open", "setIcon", "setPanel", "setTitle", "toggle"])
        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual((requests[0]["scope"] as? [String: Any])?["tabIndex"] as? Int, 2)
        XCTAssertEqual(requests[3]["userActivation"] as? Bool, true)
        XCTAssertEqual((result["options"] as? [String: Any])?["tabId"] as? Int, 7)
        XCTAssertEqual((result["callbackLayout"] as? [String: String])?["side"], "right")
    }

    func testInvalidTargetsAndUnsupportedImagesRejectBeforeBroker() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            for (const call of [
                () => sidePanel.open({}),
                () => sidePanel.open({tabId: 7, windowId: 99}),
                () => sidebarAction.getTitle({tabId: 7, windowId: 12}),
                () => sidebarAction.setIcon({imageData: {}}),
                () => sidePanel.setOptions({path: null}),
                () => sidePanel.setPanelBehavior({openPanelOnActionClick: 1})
            ]) { try { await call(); } catch (error) { errors.push(error.message); } }
            return {errors, requests};
            """)
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertEqual(errors.count, 6)
        XCTAssertEqual(errors[0], "At least one of `tabId` and `windowId` must be provided")
        XCTAssertEqual(errors[1], "The specified tab does not belong to the specified window.")
        XCTAssertEqual(errors[2], "Only one of tabId and windowId can be specified.")
        XCTAssertTrue((result["requests"] as? [Any])?.isEmpty == true)
    }

    func testEventWatchUsesItsOwnPortAndReconstructsNativeTabIDs() async throws {
        let result = try await evaluate(
            """
            const received = [];
            sidePanel.onOpened.addListener(info => received.push(info));
            await watchOptions.onMessage({api: 'sidebar.event', kind: 'opened', windowKind: 'primary', tabIndex: 2, path: 'tab.html'});
            await watchOptions.onMessage({api: 'sidebar.event', kind: 'opened', windowKind: 'primary', path: 'panel.html'});
            return {received, subscription: watchOptions.subscription(), connections};
            """)
        let received = try XCTUnwrap(result["received"] as? [[String: Any]])
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0]["tabId"] as? Int, 7)
        XCTAssertNil(received[1]["tabId"])
        XCTAssertEqual(received[1]["windowId"] as? Int, 12)
        XCTAssertEqual((result["subscription"] as? [String: String])?["api"], "sidebar.watch")
    }

    private func evaluate(_ body: String) async throws -> [String: Any] {
        let script = """
            let activation = false;
            Object.defineProperty(globalThis.navigator, 'userActivation', {configurable: true, get: () => ({isActive: activation})});
            const primaryRoot = {
                tabs: {
                    async get(id) { if (id !== 7) throw new Error('bad tab'); return {id, windowId: 12, index: 2, url: 'https://example.com/'}; },
                    async query(options) { return [{id: 7, windowId: 12, index: 2, url: 'https://example.com/'}]; }
                },
                windows: { async getCurrent() { return {id: 12, type: 'normal'}; } }
            };
            const nativeChrome = primaryRoot, nativeBrowser = primaryRoot;
            const requests = [];
            const requestCapability = async (api, payload, args, transform = value => value) => {
                requests.push({api, ...payload});
                return transform(api === 'sidePanel.getOptions' ? {path: 'panel.html', enabled: true, tabSpecific: true}
                    : api === 'sidebar.layout' ? {side: 'right'} : {ok: true});
            };
            const invokeCallbackWithLastError = (callback, message) => { callback(undefined); };
            let watchOptions, connections = 0;
            const capabilityWatch = options => {
                watchOptions = options;
                return {connect() { connections++; }, disconnect() {}, resubscribe() {}};
            };
            \(BrowserExtensionSidebarCompatibilityScript.source)
            return JSON.stringify(await (async () => { \(body) })());
            """
        let output = try await WKWebView().callAsyncJavaScript(script, arguments: [:], contentWorld: .page)
        let data = Data(try XCTUnwrap(output as? String).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
