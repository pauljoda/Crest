import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionDebuggerCompatibilityScriptTests: XCTestCase {
    func testFullSurfaceFrozenEnumsAndAttachRoundTrip() async throws {
        let result = try await evaluate(
            """
            const surface = Object.keys(debuggerNamespace).sort();
            const frozen = [Object.isFrozen(debuggerNamespace.DetachReason), Object.isFrozen(debuggerNamespace.TargetInfoType)];
            await debuggerNamespace.attach({tabId: 7}, "1.3");
            const value = await debuggerNamespace.sendCommand({tabId: 7}, "Runtime.evaluate", {expression: "1"});
            await debuggerNamespace.detach({tabId: 7});
            return {
                surface, frozen, requests, value, connections,
                reasons: debuggerNamespace.DetachReason,
                types: debuggerNamespace.TargetInfoType
            };
            """)
        XCTAssertEqual(
            result["surface"] as? [String],
            ["DetachReason", "TargetInfoType", "attach", "detach", "getTargets", "onDetach", "onEvent", "sendCommand"])
        XCTAssertEqual(result["frozen"] as? [Bool], [true, true])
        XCTAssertEqual(
            result["reasons"] as? [String: String],
            ["TARGET_CLOSED": "target_closed", "CANCELED_BY_USER": "canceled_by_user"])
        XCTAssertEqual(
            result["types"] as? [String: String],
            ["PAGE": "page", "BACKGROUND_PAGE": "background_page", "WORKER": "worker", "OTHER": "other"])
        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0]["api"] as? String, "debugger.attach")
        XCTAssertEqual(requests[0]["tabIndex"] as? Int, 2)
        XCTAssertEqual(requests[0]["url"] as? String, "https://example.com/")
        XCTAssertEqual(requests[0]["tabId"] as? Int, 7)
        XCTAssertEqual(requests[0]["requiredVersion"] as? String, "1.3")
        XCTAssertEqual(requests[1]["api"] as? String, "debugger.sendCommand")
        XCTAssertEqual(requests[1]["sessionToken"] as? String, "token-1")
        XCTAssertEqual(requests[1]["method"] as? String, "Runtime.evaluate")
        XCTAssertEqual((requests[1]["params"] as? [String: Any])?["expression"] as? String, "1")
        XCTAssertEqual(requests[2]["api"] as? String, "debugger.detach")
        XCTAssertEqual(requests[2]["sessionToken"] as? String, "token-1")
        XCTAssertEqual((result["value"] as? [String: Any])?["value"] as? Int, 42)
        // Attaching connects the watch even when listeners registered later.
        XCTAssertEqual(result["connections"] as? Int, 1)
    }

    func testValidationMessagesMatchChrome() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            for (const call of [
                () => debuggerNamespace.attach({}, "1.3"),
                () => debuggerNamespace.attach({extensionId: "abc"}, "1.3"),
                () => debuggerNamespace.attach({targetId: "abc"}, "1.3"),
                () => debuggerNamespace.attach({tabId: 99}, "1.3"),
                () => debuggerNamespace.attach({tabId: 7}, 13),
                () => debuggerNamespace.sendCommand({tabId: 7}, "Runtime.evaluate"),
                () => debuggerNamespace.detach({tabId: 7})
            ]) { try { await call(); } catch (error) { errors.push(error.message); } }
            return {errors, requests};
            """)
        XCTAssertEqual(
            result["errors"] as? [String],
            [
                "Either tab id or extension id must be specified.",
                "Cannot attach to this target.",
                "Cannot attach to this target.",
                "No tab with given id 99.",
                "Requested protocol version is not supported: 13.",
                "Debugger is not attached to the tab with id: 7.",
                "Debugger is not attached to the tab with id: 7.",
            ])
        XCTAssertTrue((result["requests"] as? [Any])?.isEmpty == true)
    }

    func testBrokerFailuresReachCallbacksAsLastError() async throws {
        let result = try await evaluate(
            """
            await debuggerNamespace.attach({tabId: 7}, "1.3");
            failSendCommandWith = "'Input.dispatchKeyEvent' wasn't found";
            const returned = await new Promise(resolve => {
                debuggerNamespace.sendCommand({tabId: 7}, "Input.dispatchKeyEvent", {}, value => resolve(value));
            });
            failSendCommandWith = "Detached while handling command.";
            let detachedMessage;
            try { await debuggerNamespace.sendCommand({tabId: 7}, "Runtime.evaluate", {}); }
            catch (error) { detachedMessage = error.message; }
            let afterDetach;
            try { await debuggerNamespace.sendCommand({tabId: 7}, "Runtime.evaluate", {}); }
            catch (error) { afterDetach = error.message; }
            return {returned, lastErrors, detachedMessage, afterDetach};
            """)
        XCTAssertNil(result["returned"])
        XCTAssertEqual(result["lastErrors"] as? [String], ["'Input.dispatchKeyEvent' wasn't found"])
        XCTAssertEqual(result["detachedMessage"] as? String, "Detached while handling command.")
        // A command that reported a detach drops the token, so the next call
        // fails locally with Chrome's not-attached text rather than at Crest.
        XCTAssertEqual(result["afterDetach"] as? String, "Debugger is not attached to the tab with id: 7.")
    }

    func testEventsAndDetachReachListenersAndRetireTheToken() async throws {
        let result = try await evaluate(
            """
            const events = [], detaches = [];
            debuggerNamespace.onEvent.addListener((source, method, params) => events.push({source, method, params}));
            debuggerNamespace.onDetach.addListener((source, reason) => detaches.push({source, reason}));
            await debuggerNamespace.attach({tabId: 7}, "1.3");
            const watch = watchOptions["debugger"];
            watch.onMessage({api: 'debugger.event', sessionToken: 'token-1', kind: 'event', method: 'Runtime.consoleAPICalled', params: {type: 'log'}});
            watch.onMessage({api: 'debugger.event', sessionToken: 'unknown', kind: 'event', method: 'Runtime.ignored'});
            watch.onMessage({api: 'debugger.event', sessionToken: 'token-1', kind: 'detach', reason: 'canceled_by_user'});
            watch.onMessage({api: 'debugger.event', sessionToken: 'token-1', kind: 'event', method: 'Runtime.afterDetach'});
            let afterDetach;
            try { await debuggerNamespace.sendCommand({tabId: 7}, "Runtime.evaluate", {}); }
            catch (error) { afterDetach = error.message; }
            return {
                events, detaches, afterDetach,
                subscription: watch.subscription(),
                hasListener: debuggerNamespace.onEvent.hasListeners()
            };
            """)
        let events = try XCTUnwrap(result["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual((events[0]["source"] as? [String: Any])?["tabId"] as? Int, 7)
        XCTAssertEqual(events[0]["method"] as? String, "Runtime.consoleAPICalled")
        XCTAssertEqual((events[0]["params"] as? [String: Any])?["type"] as? String, "log")
        let detaches = try XCTUnwrap(result["detaches"] as? [[String: Any]])
        XCTAssertEqual(detaches.count, 1)
        XCTAssertEqual((detaches[0]["source"] as? [String: Any])?["tabId"] as? Int, 7)
        XCTAssertEqual(detaches[0]["reason"] as? String, "canceled_by_user")
        XCTAssertEqual(result["afterDetach"] as? String, "Debugger is not attached to the tab with id: 7.")
        XCTAssertEqual((result["subscription"] as? [String: String])?["api"], "debugger.watch")
        XCTAssertEqual(result["hasListener"] as? Bool, true)
    }

    func testGetTargetsReconstructsNativeTabIdentifiers() async throws {
        let result = try await evaluate(
            """
            const targets = await debuggerNamespace.getTargets();
            const callbackTargets = await new Promise(resolve => debuggerNamespace.getTargets(resolve));
            return {targets, callbackCount: callbackTargets.length, requests};
            """)
        let targets = try XCTUnwrap(result["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.count, 3)
        XCTAssertEqual(targets[0]["type"] as? String, "page")
        XCTAssertEqual(targets[0]["id"] as? String, "crest-tab-a")
        XCTAssertEqual(targets[0]["tabId"] as? Int, 7)
        XCTAssertEqual(targets[0]["title"] as? String, "Example")
        XCTAssertEqual(targets[0]["url"] as? String, "https://example.com/")
        XCTAssertEqual(targets[0]["attached"] as? Bool, true)
        XCTAssertEqual(targets[1]["tabId"] as? Int, 9)
        XCTAssertEqual(targets[1]["attached"] as? Bool, false)
        // A target whose live tab no longer matches keeps its Crest identity
        // and simply carries no native tab id, exactly as Chrome does for a
        // target that is not a page in this window.
        XCTAssertNil(targets[2]["tabId"])
        XCTAssertEqual(targets[2]["id"] as? String, "crest-tab-c")
        XCTAssertEqual(result["callbackCount"] as? Int, 3)
        XCTAssertEqual((result["requests"] as? [[String: Any]])?.count, 2)
    }

    private func evaluate(_ body: String) async throws -> [String: Any] {
        let script = """
            const primaryRoot = {
                tabs: {
                    async get(id) { if (id !== 7) throw new Error('bad tab'); return {id, windowId: 12, index: 2, url: 'https://example.com/'}; },
                    async query() {
                        return [
                            {id: 7, windowId: 12, index: 2, url: 'https://example.com/'},
                            {id: 9, windowId: 12, index: 3, url: 'https://other.test/'},
                            {id: 11, windowId: 12, index: 4, url: 'https://moved.test/'}
                        ];
                    }
                },
                windows: { async getCurrent() { return {id: 12, type: 'normal'}; } }
            };
            const nativeChrome = primaryRoot, nativeBrowser = primaryRoot;
            const requests = [], lastErrors = [];
            let failSendCommandWith;
            const requestCapability = async (api, payload, args, transform = value => value) => {
                requests.push({api, ...payload});
                if (api === 'debugger.sendCommand' && failSendCommandWith) throw new Error(failSendCommandWith);
                return transform(
                    api === 'debugger.attach' ? {sessionToken: 'token-1'}
                        : api === 'debugger.sendCommand' ? {result: {value: 42}}
                        : api === 'debugger.getTargets' ? {targets: [
                            {id: 'crest-tab-a', tabIndex: 2, title: 'Example', url: 'https://example.com/', attached: true},
                            {id: 'crest-tab-b', tabIndex: 3, title: 'Other', url: 'https://other.test/', attached: false},
                            {id: 'crest-tab-c', tabIndex: 4, title: 'Moved', url: 'https://moved.test/away', attached: false}
                        ]}
                        : {ok: true});
            };
            const invokeCallbackWithLastError = (callback, message) => { lastErrors.push(message); callback(undefined); };
            const watchOptions = {}; let connections = 0;
            const capabilityWatch = options => {
                watchOptions[options.api] = options;
                return {connect() { connections++; }, disconnect() {}, resubscribe() {}};
            };
            \(BrowserExtensionSidebarCompatibilityScript.source)
            \(BrowserExtensionDebuggerCompatibilityScript.source)
            return JSON.stringify(await (async () => { \(body) })());
            """
        let output = try await WKWebView().callAsyncJavaScript(script, arguments: [:], contentWorld: .page)
        let data = Data(try XCTUnwrap(output as? String).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
