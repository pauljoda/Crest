import WebKit
import XCTest

@testable import Crest

/// The runtime half of the `modifyHeaders` partition: what reaches WebKit,
/// what Crest keeps, what the extension reads back, and which of its own
/// requests gain the headers.
@MainActor
final class BrowserExtensionDeclarativeNetRequestCompatibilityScriptTests: XCTestCase {
    /// Claude's real session rule: one standard header WebKit accepts and two
    /// `anthropic-*` headers it rejects outright, which today takes the whole
    /// rule down with them.
    func testAMixedRuleSendsOnlyAcceptedHeadersNativelyAndKeepsTheRest() async throws {
        let result = try await evaluate(
            """
            await chrome.declarativeNetRequest.updateSessionRules({
                removeRuleIds: [1],
                addRules: [{
                    id: 1, priority: 1,
                    action: {type: "modifyHeaders", requestHeaders: [
                        {header: "Accept-Language", operation: "set", value: "en-US"},
                        {header: "anthropic-client-platform", operation: "set",
                            value: "claude_browser_extension"},
                        {header: "anthropic-client-version", operation: "set", value: "1.2.3"}
                    ]},
                    condition: {urlFilter: "https://api.anthropic.com/*",
                        resourceTypes: ["xmlhttprequest", "other"]}
                }]
            });
            return {nativeCalls, brokerRequests};
            """)
        let nativeCalls = try XCTUnwrap(result["nativeCalls"] as? [[String: Any]])
        XCTAssertEqual(nativeCalls.count, 1)
        XCTAssertEqual(nativeCalls[0]["method"] as? String, "updateSessionRules")
        let nativeRules = try XCTUnwrap(
            (nativeCalls[0]["options"] as? [String: Any])?["addRules"] as? [[String: Any]])
        XCTAssertEqual(nativeRules.count, 1)
        let nativeHeaders = try XCTUnwrap(
            (nativeRules[0]["action"] as? [String: Any])?["requestHeaders"] as? [[String: Any]])
        XCTAssertEqual(nativeHeaders.map { $0["header"] as? String }, ["Accept-Language"])
        XCTAssertEqual(
            (nativeCalls[0]["options"] as? [String: Any])?["removeRuleIds"] as? [Int], [1])

        let brokerRequests = try XCTUnwrap(result["brokerRequests"] as? [[String: Any]])
        let set = try XCTUnwrap(
            brokerRequests.first { $0["api"] as? String == "dnr.setEmulatedHeaderRules" })
        XCTAssertEqual(set["ruleset"] as? String, "session")
        let emulated = try XCTUnwrap(set["rules"] as? [[String: Any]])
        XCTAssertEqual(emulated.count, 1)
        XCTAssertEqual(emulated[0]["id"] as? Int, 1)
        XCTAssertEqual(emulated[0]["priority"] as? Int, 1)
        XCTAssertEqual(
            (emulated[0]["requestHeaders"] as? [[String: Any]])?.map { $0["header"] as? String },
            ["anthropic-client-platform", "anthropic-client-version"])
        XCTAssertEqual(
            (emulated[0]["condition"] as? [String: Any])?["urlFilter"] as? String,
            "https://api.anthropic.com/*")
    }

    /// WebKit rejects a `modifyHeaders` rule with no header operation left, so
    /// a rule Crest took over entirely is not sent at all.
    func testARuleWithNoAcceptedHeaderIsNotSentNatively() async throws {
        let result = try await evaluate(
            """
            await chrome.declarativeNetRequest.updateDynamicRules({
                addRules: [{
                    id: 7,
                    action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-crest-token", operation: "set", value: "abc"}
                    ]},
                    condition: {urlFilter: "||example.test^"}
                }]
            });
            return {nativeCalls, brokerRequests};
            """)
        let nativeCalls = try XCTUnwrap(result["nativeCalls"] as? [[String: Any]])
        XCTAssertEqual(nativeCalls.count, 1)
        XCTAssertEqual(nativeCalls[0]["method"] as? String, "updateDynamicRules")
        XCTAssertEqual(
            ((nativeCalls[0]["options"] as? [String: Any])?["addRules"] as? [Any])?.count, 0)
        let set = try XCTUnwrap(
            (result["brokerRequests"] as? [[String: Any]])?
                .first { $0["api"] as? String == "dnr.setEmulatedHeaderRules" })
        XCTAssertEqual(set["ruleset"] as? String, "dynamic")
        XCTAssertEqual((set["rules"] as? [[String: Any]])?.first?["id"] as? Int, 7)
    }

    /// A native refusal is the extension's error, and nothing is recorded for
    /// a call the browser did not accept.
    func testANativeRefusalIsSurfacedAndRegistersNothing() async throws {
        let result = try await evaluate(
            """
            let message;
            try {
                await chrome.declarativeNetRequest.updateSessionRules({
                    addRules: [{
                        id: 2,
                        action: {type: "modifyHeaders", requestHeaders: [
                            {header: "Accept", operation: "set", value: "*/*"},
                            {header: "x-crest", operation: "set", value: "1"}
                        ]},
                        condition: {urlFilter: "*"}
                    }]
                });
            } catch (error) { message = error.message; }
            return {message, brokerRequests};
            """, nativeRefusal: "Rule with id 2 is invalid.")
        XCTAssertEqual(result["message"] as? String, "Rule with id 2 is invalid.")
        XCTAssertFalse(
            (result["brokerRequests"] as? [[String: Any]] ?? [])
                .contains { $0["api"] as? String == "dnr.setEmulatedHeaderRules" })
    }

    func testGetSessionRulesMergesTheEmulatedOperationsBackIntoTheirRule() async throws {
        let result = try await evaluate(
            """
            await chrome.declarativeNetRequest.updateSessionRules({
                addRules: [
                    {
                        id: 1, priority: 3,
                        action: {type: "modifyHeaders", requestHeaders: [
                            {header: "Accept", operation: "set", value: "*/*"},
                            {header: "x-partitioned", operation: "set", value: "yes"}
                        ]},
                        condition: {urlFilter: "https://api.anthropic.com/*"}
                    },
                    {
                        id: 2,
                        action: {type: "modifyHeaders", requestHeaders: [
                            {header: "x-owned", operation: "remove"}
                        ]},
                        condition: {urlFilter: "*"}
                    }
                ]
            });
            const rules = await chrome.declarativeNetRequest.getSessionRules();
            const filtered = await chrome.declarativeNetRequest.getSessionRules({ruleIds: [2]});
            return {rules, filtered};
            """)
        let rules = try XCTUnwrap(result["rules"] as? [[String: Any]])
        XCTAssertEqual(rules.map { $0["id"] as? Int }, [1, 2])
        XCTAssertEqual(
            ((rules[0]["action"] as? [String: Any])?["requestHeaders"] as? [[String: Any]])?
                .map { $0["header"] as? String },
            ["Accept", "x-partitioned"])
        // Rule 2 never reached WebKit, so the merged view synthesizes it.
        XCTAssertEqual((rules[1]["action"] as? [String: Any])?["type"] as? String, "modifyHeaders")
        XCTAssertEqual(
            ((rules[1]["action"] as? [String: Any])?["requestHeaders"] as? [[String: Any]])?
                .first?["operation"] as? String, "remove")
        XCTAssertEqual(
            (result["filtered"] as? [[String: Any]])?.map { $0["id"] as? Int }, [2])
    }

    func testAMatchingFetchGainsTheHeadersAndANonMatchingOneDoesNot() async throws {
        let result = try await evaluate(
            """
            await chrome.declarativeNetRequest.updateSessionRules({
                addRules: [{
                    id: 1, priority: 1,
                    action: {type: "modifyHeaders", requestHeaders: [
                        {header: "anthropic-client-platform", operation: "set",
                            value: "claude_browser_extension"},
                        {header: "User-Agent", operation: "set", value: "claude-browser/1"},
                        {header: "x-trace", operation: "append", value: "b"}
                    ]},
                    condition: {urlFilter: "https://api.anthropic.com/*",
                        resourceTypes: ["xmlhttprequest", "other"]}
                }]
            });
            const matched = await fetch("https://api.anthropic.com/v1/messages", {
                method: "POST", headers: {"x-trace": "a", "content-type": "application/json"}
            });
            const missed = await fetch("https://example.test/v1/messages", {method: "POST"});
            return {matched, missed};
            """)
        let matched = try XCTUnwrap(result["matched"] as? [String: Any])
        XCTAssertEqual(matched["anthropic-client-platform"] as? String, "claude_browser_extension")
        // `append` combines with what the caller already sent, per HTTP.
        XCTAssertEqual(matched["x-trace"] as? String, "a, b")
        XCTAssertEqual(matched["content-type"] as? String, "application/json")
        // Fetch forbids a script from setting `User-Agent`, whatever the rule
        // asks for.
        XCTAssertNil(matched["user-agent"])
        let missed = try XCTUnwrap(result["missed"] as? [String: Any])
        XCTAssertNil(missed["anthropic-client-platform"])
    }

    /// `resourceTypes` that name neither `xmlhttprequest` nor `other`, an
    /// excluded method, and a case-sensitive filter all keep a rule away from
    /// a request it was not written for.
    func testConditionsThatDoNotDescribeAnExtensionRequestDoNotApply() async throws {
        let result = try await evaluate(
            """
            await chrome.declarativeNetRequest.updateSessionRules({
                addRules: [
                    {id: 1, action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-images", operation: "set", value: "1"}]},
                        condition: {urlFilter: "*", resourceTypes: ["image"]}},
                    {id: 2, action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-not-post", operation: "set", value: "1"}]},
                        condition: {urlFilter: "*", excludedRequestMethods: ["post"]}},
                    {id: 3, action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-cased", operation: "set", value: "1"}]},
                        condition: {urlFilter: "https://API.anthropic.com/*",
                            isUrlFilterCaseSensitive: true}},
                    {id: 4, action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-regex", operation: "set", value: "1"}]},
                        condition: {regexFilter: "^https://api\\\\.anthropic\\\\.com/v\\\\d+/"}}
                ]
            });
            const headers = await fetch("https://api.anthropic.com/v1/messages", {method: "POST"});
            return {headers};
            """)
        let headers = try XCTUnwrap(result["headers"] as? [String: Any])
        XCTAssertNil(headers["x-images"])
        XCTAssertNil(headers["x-not-post"])
        XCTAssertNil(headers["x-cased"])
        XCTAssertEqual(headers["x-regex"] as? String, "1")
    }

    func testTheHighestPriorityRuleWinsAHeaderAndTiesGoToTheLowerRuleID() async throws {
        let result = try await evaluate(
            """
            await chrome.declarativeNetRequest.updateSessionRules({
                addRules: [
                    {id: 9, priority: 1, action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-pick", operation: "set", value: "low"},
                        {header: "x-tie", operation: "set", value: "nine"}]},
                        condition: {urlFilter: "*"}},
                    {id: 3, priority: 5, action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-pick", operation: "set", value: "high"}]},
                        condition: {urlFilter: "*"}},
                    {id: 4, priority: 1, action: {type: "modifyHeaders", requestHeaders: [
                        {header: "x-tie", operation: "set", value: "four"}]},
                        condition: {urlFilter: "*"}}
                ]
            });
            const headers = await fetch("https://api.anthropic.com/v1/messages");
            return {headers};
            """)
        let headers = try XCTUnwrap(result["headers"] as? [String: Any])
        XCTAssertEqual(headers["x-pick"] as? String, "high")
        XCTAssertEqual(headers["x-tie"] as? String, "four")
    }

    /// Every context reads the shared table, not only the one that set it.
    func testTheTableIsFetchedAtStartupAndRefreshedByTheWatch() async throws {
        let result = try await evaluate(
            """
            const before = await fetch("https://api.anthropic.com/v1/messages");
            watch.onMessage({api: "dnr.event", rulesets: {session: [{
                id: 1, priority: 1,
                requestHeaders: [{header: "x-watched", operation: "set", value: "yes"}],
                condition: {urlFilter: "https://api.anthropic.com/*"}
            }], dynamic: []}});
            const after = await fetch("https://api.anthropic.com/v1/messages");
            return {
                before, after, startup: brokerRequests[0]?.api,
                subscription: watch.subscription().api, connected
            };
            """, startupRulesets: #"{"session": [], "dynamic": []}"#)
        XCTAssertEqual(result["startup"] as? String, "dnr.emulatedHeaderRules")
        XCTAssertEqual(result["subscription"] as? String, "dnr.watch")
        XCTAssertEqual(result["connected"] as? Int, 1)
        XCTAssertNil((result["before"] as? [String: Any])?["x-watched"])
        XCTAssertEqual((result["after"] as? [String: Any])?["x-watched"] as? String, "yes")
    }

    // MARK: - Fixture

    /// A WebKit-27 shaped `declarativeNetRequest`: real methods, no constants,
    /// and a validator that stands in for `isHeaderNameValid` by recording
    /// exactly what it was handed.
    private func evaluate(
        _ body: String,
        nativeRefusal: String? = nil,
        startupRulesets: String = #"{"session": [], "dynamic": []}"#
    ) async throws -> [String: Any] {
        let refusal = nativeRefusal.map { "\"\($0)\"" } ?? "undefined"
        let script = """
            const nativeRefusal = \(refusal);
            const nativeCalls = [];
            let nativeSessionRules = [];
            let nativeDynamicRules = [];
            const applyNative = (method, store, options) => {
                nativeCalls.push({method, options: JSON.parse(JSON.stringify(options ?? null))});
                if (nativeRefusal !== undefined) return Promise.reject(new Error(nativeRefusal));
                const removed = new Set(options?.removeRuleIds ?? []);
                for (const rule of options?.addRules ?? []) removed.add(rule.id);
                const next = store().filter(rule => !removed.has(rule.id))
                    .concat(JSON.parse(JSON.stringify(options?.addRules ?? [])));
                store(next);
                return Promise.resolve(undefined);
            };
            const sessionStore = (value) => {
                if (value !== undefined) nativeSessionRules = value;
                return nativeSessionRules;
            };
            const dynamicStore = (value) => {
                if (value !== undefined) nativeDynamicRules = value;
                return nativeDynamicRules;
            };
            const filterNative = (rules, filter) => Array.isArray(filter?.ruleIds)
                ? rules.filter(rule => filter.ruleIds.includes(rule.id))
                : rules;
            const nativeDeclarativeNetRequestNamespace = {
                updateSessionRules(options) {
                    return applyNative("updateSessionRules", sessionStore, options);
                },
                updateDynamicRules(options) {
                    return applyNative("updateDynamicRules", dynamicStore, options);
                },
                getSessionRules(filter) {
                    return Promise.resolve(filterNative(nativeSessionRules, filter));
                },
                getDynamicRules(filter) {
                    return Promise.resolve(filterNative(nativeDynamicRules, filter));
                }
            };
            const primaryRoot = {declarativeNetRequest: nativeDeclarativeNetRequestNamespace};
            const nativeChrome = primaryRoot, nativeBrowser = primaryRoot;

            const brokerRequests = [];
            let emulatedRulesets = \(startupRulesets);
            const requestCapability = async (api, payload, args, transform = value => value) => {
                brokerRequests.push(JSON.parse(JSON.stringify({api, ...payload})));
                if (api === "dnr.setEmulatedHeaderRules") {
                    emulatedRulesets = {
                        ...emulatedRulesets,
                        [payload.ruleset]: JSON.parse(JSON.stringify(payload.rules))
                    };
                    return transform({ok: true});
                }
                if (api === "dnr.emulatedHeaderRules") {
                    return transform({rulesets: JSON.parse(JSON.stringify(emulatedRulesets))});
                }
                return transform({});
            };
            let lastErrorMessage;
            const invokeCallbackWithLastError = (callback, message) => {
                lastErrorMessage = message;
                callback(undefined);
            };
            let watch = {subscription: () => ({}), onMessage: () => {}};
            let connected = 0;
            const capabilityWatch = (options) => {
                watch = options;
                return {connect() { connected += 1; }, disconnect() {}, resubscribe() {}};
            };
            const isPrivilegedExtensionContext = true;
            const executionProcess = "background";
            const capturesExtensionConsole = false;
            const reportRuntimeTrace = () => {};
            const namespaceUsesCompatibility = () => true;
            const memberUsesCompatibility = () => true;

            // Records what a request would have carried instead of sending it.
            globalThis.fetch = (resource, options) => {
                const headers = {};
                for (const [name, value] of new Headers(options?.headers ?? {})) {
                    headers[name] = value;
                }
                return Promise.resolve(headers);
            };

            \(BrowserExtensionDeclarativeNetRequestCompatibilityScript.source)
            const chrome = {declarativeNetRequest: nativeDeclarativeNetRequestNamespace};
            normalizeDeclarativeNetRequestNamespace(nativeDeclarativeNetRequestNamespace);
            // Let the startup table request settle before the body runs, the
            // way a worker's rules land long before a panel opens.
            await Promise.resolve();
            await Promise.resolve();
            return JSON.stringify(await (async () => { \(body) })());
            """
        let output = try await WKWebView().callAsyncJavaScript(
            script, arguments: [:], contentWorld: .page)
        let data = Data(try XCTUnwrap(output as? String).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
