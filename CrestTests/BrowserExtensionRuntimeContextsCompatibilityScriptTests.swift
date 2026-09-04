import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionRuntimeContextsCompatibilityScriptTests: XCTestCase {
    func testRuntimeEnumsAreFrozenAndMatchTheChromeSchema() async throws {
        let result = try await evaluate(
            """
            const enums = {};
            const frozen = {};
            for (const name of ["ContextType", "OnInstalledReason", "OnRestartRequiredReason",
                "PlatformArch", "PlatformNaclArch", "PlatformOs", "RequestUpdateCheckStatus"]) {
                enums[name] = {...runtime[name]};
                frozen[name] = Object.isFrozen(runtime[name]);
            }
            let mutated = false;
            try { runtime.ContextType.SIDE_PANEL = "nope"; } catch { mutated = true; }
            return {enums, frozen, sidePanel: runtime.ContextType.SIDE_PANEL, mutated};
            """)
        let enums = try XCTUnwrap(result["enums"] as? [String: [String: String]])
        XCTAssertEqual(
            enums["ContextType"],
            [
                "TAB": "TAB", "POPUP": "POPUP", "BACKGROUND": "BACKGROUND",
                "OFFSCREEN_DOCUMENT": "OFFSCREEN_DOCUMENT", "SIDE_PANEL": "SIDE_PANEL",
                "DEVELOPER_TOOLS": "DEVELOPER_TOOLS",
            ])
        XCTAssertEqual(
            enums["OnInstalledReason"],
            [
                "INSTALL": "install", "UPDATE": "update", "CHROME_UPDATE": "chrome_update",
                "SHARED_MODULE_UPDATE": "shared_module_update",
            ])
        XCTAssertEqual(
            enums["OnRestartRequiredReason"],
            ["APP_UPDATE": "app_update", "OS_UPDATE": "os_update", "PERIODIC": "periodic"])
        XCTAssertEqual(
            enums["PlatformArch"],
            [
                "ARM": "arm", "ARM64": "arm64", "X86_32": "x86-32", "X86_64": "x86-64", "MIPS": "mips",
                "MIPS64": "mips64", "RISCV64": "riscv64",
            ])
        XCTAssertEqual(
            enums["PlatformNaclArch"],
            ["ARM": "arm", "X86_32": "x86-32", "X86_64": "x86-64", "MIPS": "mips", "MIPS64": "mips64"])
        XCTAssertEqual(
            enums["PlatformOs"],
            [
                "MAC": "mac", "WIN": "win", "ANDROID": "android", "CROS": "cros", "LINUX": "linux",
                "OPENBSD": "openbsd",
            ])
        XCTAssertEqual(
            enums["RequestUpdateCheckStatus"],
            ["THROTTLED": "throttled", "NO_UPDATE": "no_update", "UPDATE_AVAILABLE": "update_available"])
        XCTAssertEqual(
            result["frozen"] as? [String: Bool],
            [
                "ContextType": true, "OnInstalledReason": true, "OnRestartRequiredReason": true,
                "PlatformArch": true, "PlatformNaclArch": true, "PlatformOs": true,
                "RequestUpdateCheckStatus": true,
            ])
        XCTAssertEqual(result["sidePanel"] as? String, "SIDE_PANEL")
    }

    func testDeclarativeNetRequestEnumsAndLimitsMatchTheChromeSchema() async throws {
        let result = try await evaluate(
            """
            return {
                modifyHeaders: declarativeNetRequest.RuleActionType.MODIFY_HEADERS,
                set: declarativeNetRequest.HeaderOperation.SET,
                webSocket: declarativeNetRequest.ResourceType.WEBSOCKET,
                firstParty: declarativeNetRequest.DomainType.FIRST_PARTY,
                syntaxError: declarativeNetRequest.UnsupportedRegexReason.SYNTAX_ERROR,
                other: declarativeNetRequest.RequestMethod.OTHER,
                dynamicRuleset: declarativeNetRequest.DYNAMIC_RULESET_ID,
                sessionRuleset: declarativeNetRequest.SESSION_RULESET_ID,
                dynamicRules: declarativeNetRequest.MAX_NUMBER_OF_DYNAMIC_RULES,
                regexRules: declarativeNetRequest.MAX_NUMBER_OF_REGEX_RULES,
                quotaInterval: declarativeNetRequest.GETMATCHEDRULES_QUOTA_INTERVAL,
                frozen: Object.isFrozen(declarativeNetRequest.RuleActionType),
                actions: Object.keys(declarativeNetRequest.RuleActionType),
                resources: Object.keys(declarativeNetRequest.ResourceType).length
            };
            """)
        XCTAssertEqual(result["modifyHeaders"] as? String, "modifyHeaders")
        XCTAssertEqual(result["set"] as? String, "set")
        XCTAssertEqual(result["webSocket"] as? String, "websocket")
        XCTAssertEqual(result["firstParty"] as? String, "firstParty")
        XCTAssertEqual(result["syntaxError"] as? String, "syntaxError")
        XCTAssertEqual(result["other"] as? String, "other")
        XCTAssertEqual(result["dynamicRuleset"] as? String, "_dynamic")
        XCTAssertEqual(result["sessionRuleset"] as? String, "_session")
        XCTAssertEqual(result["dynamicRules"] as? Int, 30000)
        XCTAssertEqual(result["regexRules"] as? Int, 1000)
        XCTAssertEqual(result["quotaInterval"] as? Int, 10)
        XCTAssertEqual(result["frozen"] as? Bool, true)
        XCTAssertEqual(
            result["actions"] as? [String],
            ["BLOCK", "REDIRECT", "ALLOW", "UPGRADE_SCHEME", "MODIFY_HEADERS", "ALLOW_ALL_REQUESTS"])
        XCTAssertEqual(result["resources"] as? Int, 15)
    }

    /// A namespace of constants with no `updateDynamicRules` behind it is
    /// worse than an absent one: feature detection succeeds and the next call
    /// throws.
    func testDeclarativeNetRequestPublishesNothingWithoutTheNativeNamespace() async throws {
        let result = try await evaluate(
            """
            return {members: Object.keys(declarativeNetRequest)};
            """, hasNativeDeclarativeNetRequest: false)
        XCTAssertEqual(result["members"] as? [String], [])
    }

    func testGetContextsResolvesTabAndWindowIDsAndAppliesTheFilter() async throws {
        let result = try await evaluate(
            """
            const all = await runtime.getContexts({});
            const sidePanels = await runtime.getContexts(
                {contextTypes: [runtime.ContextType.SIDE_PANEL]});
            const byTab = await runtime.getContexts({tabIds: [7]});
            const byType = await runtime.getContexts(
                {contextTypes: ["BACKGROUND"], incognito: false});
            const missed = await runtime.getContexts({contextTypes: ["POPUP"]});
            const conjunction = await runtime.getContexts({contextTypes: ["SIDE_PANEL"], tabIds: [-1]});
            const callback = await new Promise(resolve => runtime.getContexts({}, resolve));
            return {all, sidePanels, byTab, byType, missed, conjunction,
                callbackCount: callback.length, requests};
            """, background: #"{"page": "background.html"}"#)
        let all = try XCTUnwrap(result["all"] as? [[String: Any]])
        XCTAssertEqual(all.count, 4)
        XCTAssertEqual(
            all.map { $0["contextType"] as? String },
            [
                "BACKGROUND", "OFFSCREEN_DOCUMENT", "SIDE_PANEL", "SIDE_PANEL",
            ])
        XCTAssertEqual(all[0]["tabId"] as? Int, -1)
        XCTAssertEqual(all[0]["windowId"] as? Int, -1)
        XCTAssertEqual(all[0]["documentUrl"] as? String, "webkit-extension://probe/background.html")
        XCTAssertEqual(all[1]["tabId"] as? Int, -1)
        XCTAssertEqual(all[1]["documentUrl"] as? String, "webkit-extension://probe/offscreen.html")
        XCTAssertEqual(all[2]["tabId"] as? Int, 7)
        XCTAssertEqual(all[2]["windowId"] as? Int, 12)
        XCTAssertEqual(
            all[2]["documentUrl"] as? String, "webkit-extension://probe/sidepanel.html?tabId=7")
        XCTAssertEqual(all[2]["documentOrigin"] as? String, "webkit-extension://probe")
        XCTAssertEqual(all[2]["frameId"] as? Int, 0)
        XCTAssertEqual(all[2]["incognito"] as? Bool, false)
        XCTAssertEqual(all[2]["contextId"] as? String, "panel-context")
        // A Space-wide panel names a window but no tab.
        XCTAssertEqual(all[3]["tabId"] as? Int, -1)
        XCTAssertEqual(all[3]["windowId"] as? Int, 12)

        XCTAssertEqual((result["sidePanels"] as? [[String: Any]])?.count, 2)
        let byTab = try XCTUnwrap(result["byTab"] as? [[String: Any]])
        XCTAssertEqual(byTab.count, 1)
        XCTAssertEqual(byTab[0]["contextType"] as? String, "SIDE_PANEL")
        XCTAssertEqual((result["byType"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((result["missed"] as? [Any])?.count, 0)
        // AND across fields: the tab-scoped panel is excluded by tabIds.
        XCTAssertEqual((result["conjunction"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(result["callbackCount"] as? Int, 4)

        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 7)
        XCTAssertEqual(requests[0]["api"] as? String, "runtime.getContexts")
        XCTAssertEqual(
            (requests[1]["filter"] as? [String: Any])?["contextTypes"] as? [String], ["SIDE_PANEL"])
    }

    func testGetContextsRejectsAMalformedFilterBeforeTheBroker() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            for (const call of [
                () => runtime.getContexts(7),
                () => runtime.getContexts({contextTypes: "SIDE_PANEL"}),
                () => runtime.getContexts({incognito: "yes"})
            ]) { try { await call(); } catch (error) { errors.push(error.message); } }
            const lastError = await new Promise(resolve => {
                runtime.getContexts([], () => resolve(lastErrorMessage));
            });
            return {errors, lastError, requests};
            """)
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertEqual(errors.count, 3)
        XCTAssertEqual(errors[0], "runtime.getContexts: filter must be an object.")
        XCTAssertEqual(errors[1], "runtime.getContexts: contextTypes must be an array.")
        XCTAssertEqual(errors[2], "runtime.getContexts: incognito must be a boolean.")
        XCTAssertEqual(result["lastError"] as? String, "runtime.getContexts: filter must be an object.")
        XCTAssertTrue((result["requests"] as? [Any])?.isEmpty == true)
    }

    /// An MV3 worker background has no `documentUrl` in Chrome; a background
    /// document does.
    func testBackgroundDocumentURLFollowsTheDeclaredManifest() async throws {
        let worker = try await evaluate(
            """
            const contexts = await runtime.getContexts({contextTypes: ["BACKGROUND"]});
            return {documentUrl: contexts[0].documentUrl ?? null, has: "documentUrl" in contexts[0]};
            """, background: #"{"service_worker": "worker.js"}"#)
        XCTAssertNil(worker["documentUrl"] as? String)
        XCTAssertEqual(worker["has"] as? Bool, false)

        let scripts = try await evaluate(
            """
            const contexts = await runtime.getContexts({contextTypes: ["BACKGROUND"]});
            return {documentUrl: contexts[0].documentUrl};
            """, background: #"{"scripts": ["a.js"]}"#)
        XCTAssertEqual(
            scripts["documentUrl"] as? String,
            "webkit-extension://probe/_generated_background_page.html")
    }

    func testSetBadgeTextColorValidatesLikeChromeAndResolves() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            for (const call of [
                () => action.setBadgeTextColor(),
                () => action.setBadgeTextColor({}),
                () => action.setBadgeTextColor({color: ""}),
                () => action.setBadgeTextColor({color: [255, 255, 255]}),
                () => action.setBadgeTextColor({color: [255, 255, 255, 300]}),
                () => action.setBadgeTextColor({color: "#fff", tabId: -3})
            ]) { try { await call(); } catch (error) { errors.push(error.message); } }
            const accepted = [
                await action.setBadgeTextColor({color: "#ffffff"}),
                await action.setBadgeTextColor({color: [0, 0, 0, 255], tabId: 7})
            ];
            const callback = await new Promise(
                resolve => action.setBadgeTextColor({color: "red"}, () => resolve(lastErrorMessage ?? "none")));
            return {errors, accepted, callback, requests};
            """)
        let errors = try XCTUnwrap(result["errors"] as? [String])
        XCTAssertEqual(errors.count, 6)
        XCTAssertEqual(errors[0], "setBadgeTextColor requires a details object.")
        XCTAssertEqual(errors[1], "setBadgeTextColor requires a color.")
        XCTAssertEqual(errors[2], "The color must not be empty.")
        XCTAssertEqual(
            errors[3],
            "The color must be a CSS color string or an array of four integers in 0...255.")
        XCTAssertEqual(
            errors[4],
            "The color must be a CSS color string or an array of four integers in 0...255.")
        XCTAssertEqual(errors[5], "Invalid tab ID: -3")
        XCTAssertEqual((result["accepted"] as? [Any])?.count, 2)
        XCTAssertEqual(result["callback"] as? String, "none")
        // Crest draws its own badge; nothing crosses the broker.
        XCTAssertTrue((result["requests"] as? [Any])?.isEmpty == true)
    }

    /// The fixtures above evaluate the fragment directly. This one runs the
    /// real generated runtime, so the matrix's routing filter — which drops
    /// any member without a row — has to let every one of these through.
    func testTheGeneratedRuntimeInstallsEveryNewMemberOnWebKitsOwnObjects() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(
            path: "crest-webextension-runtime-contexts-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try Data("globalThis.started = true;".utf8).write(to: root.appending(path: "background.js"))
        let permissions = ["declarativeNetRequest"]
        try JSONSerialization.data(withJSONObject: [
            "manifest_version": 3,
            "name": "Runtime Contexts Fixture",
            "version": "1.0",
            "permissions": permissions,
            "background": ["scripts": ["background.js"]],
        ]).write(to: root.appending(path: "manifest.json"))
        let preparer = BrowserChromeWebStoreCompatibilityPackagePreparer(
            fileManager: fileManager, expandArchive: { _, _ in })
        XCTAssertTrue(
            try preparer.installCompatibilityLayer(
                in: root,
                requestedPermissions: permissions,
                runtimeIdentity: BrowserExtensionRuntimeIdentity(
                    extensionID: "fixture-extension-id",
                    uniqueIdentifier: "fixture-extension-id.space.personal",
                    baseURL: URL(string: "about:blank")!
                )
            )
        )
        let generated = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter {
                $0.lastPathComponent.hasPrefix("crest-webextension-compatibility-")
                    && $0.pathExtension == "js"
            }
        let source = try String(contentsOf: XCTUnwrap(generated.first), encoding: .utf8)

        // A WebKit 27 shaped root: `runtime`, `action`, and a
        // `declarativeNetRequest` with methods and no constants.
        let output = try await WKWebView().callAsyncJavaScript(
            """
            const nativeRuntime = {
                id: "fixture-extension-id",
                getURL(path = "") { return "about:blank#" + path; },
                getManifest() { return {manifest_version: 3}; },
                sendNativeMessage() { return Promise.reject(new Error("no broker")); }
            };
            const nativeAction = {getUserSettings() { return "native"; }};
            const nativeDNR = {updateDynamicRules() { return "native"; }};
            const root = {
                runtime: nativeRuntime, action: nativeAction, declarativeNetRequest: nativeDNR
            };
            Object.defineProperty(globalThis, "chrome", {configurable: true, value: root});
            Object.defineProperty(globalThis, "browser", {configurable: true, value: root});
            \(source)
            return JSON.stringify({
                getContexts: typeof chrome.runtime.getContexts,
                contextType: chrome.runtime.ContextType?.SIDE_PANEL,
                installReason: chrome.runtime.OnInstalledReason?.INSTALL,
                platformOs: chrome.runtime.PlatformOs?.MAC,
                updateStatus: chrome.runtime.RequestUpdateCheckStatus?.NO_UPDATE,
                restartReason: chrome.runtime.OnRestartRequiredReason?.PERIODIC,
                platformArch: chrome.runtime.PlatformArch?.X86_64,
                naclArch: chrome.runtime.PlatformNaclArch?.MIPS64,
                setBadgeTextColor: typeof chrome.action.setBadgeTextColor,
                onUserSettingsChanged: typeof chrome.action.onUserSettingsChanged?.addListener,
                aliasedBadge: typeof chrome.browserAction?.setBadgeTextColor,
                aliasedEvent: typeof chrome.browserAction?.onUserSettingsChanged?.addListener,
                nativeUserSettings: chrome.action.getUserSettings(),
                nativeRules: chrome.declarativeNetRequest.updateDynamicRules(),
                modifyHeaders: chrome.declarativeNetRequest.RuleActionType?.MODIFY_HEADERS,
                headerSet: chrome.declarativeNetRequest.HeaderOperation?.SET,
                webSocket: chrome.declarativeNetRequest.ResourceType?.WEBSOCKET,
                dynamicRuleset: chrome.declarativeNetRequest.DYNAMIC_RULESET_ID,
                regexRules: chrome.declarativeNetRequest.MAX_NUMBER_OF_REGEX_RULES
            });
            """, arguments: [:], contentWorld: .page)
        let result = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(try XCTUnwrap(output as? String).utf8)) as? [String: Any])

        XCTAssertEqual(result["getContexts"] as? String, "function")
        XCTAssertEqual(result["contextType"] as? String, "SIDE_PANEL")
        XCTAssertEqual(result["installReason"] as? String, "install")
        XCTAssertEqual(result["platformOs"] as? String, "mac")
        XCTAssertEqual(result["updateStatus"] as? String, "no_update")
        XCTAssertEqual(result["restartReason"] as? String, "periodic")
        XCTAssertEqual(result["platformArch"] as? String, "x86-64")
        XCTAssertEqual(result["naclArch"] as? String, "mips64")
        XCTAssertEqual(result["setBadgeTextColor"] as? String, "function")
        XCTAssertEqual(result["onUserSettingsChanged"] as? String, "function")
        XCTAssertEqual(result["aliasedBadge"] as? String, "function")
        XCTAssertEqual(result["aliasedEvent"] as? String, "function")
        // WebKit's own implementations stand.
        XCTAssertEqual(result["nativeUserSettings"] as? String, "native")
        XCTAssertEqual(result["nativeRules"] as? String, "native")
        XCTAssertEqual(result["modifyHeaders"] as? String, "modifyHeaders")
        XCTAssertEqual(result["headerSet"] as? String, "set")
        XCTAssertEqual(result["webSocket"] as? String, "websocket")
        XCTAssertEqual(result["dynamicRuleset"] as? String, "_dynamic")
        XCTAssertEqual(result["regexRules"] as? Int, 1000)
    }

    func testUserSettingsChangedIsARealRegistryThatNeverFires() async throws {
        let result = try await evaluate(
            """
            const listener = () => {};
            const surface = Object.keys(action.onUserSettingsChanged).sort();
            action.onUserSettingsChanged.addListener(listener);
            const added = action.onUserSettingsChanged.hasListener(listener);
            const any = action.onUserSettingsChanged.hasListeners();
            action.onUserSettingsChanged.removeListener(listener);
            return {surface, added, any, removed: action.onUserSettingsChanged.hasListener(listener),
                frozen: Object.isFrozen(action.onUserSettingsChanged)};
            """)
        XCTAssertEqual(
            result["surface"] as? [String],
            ["addListener", "hasListener", "hasListeners", "removeListener"])
        XCTAssertEqual(result["added"] as? Bool, true)
        XCTAssertEqual(result["any"] as? Bool, true)
        XCTAssertEqual(result["removed"] as? Bool, false)
        XCTAssertEqual(result["frozen"] as? Bool, true)
    }

    private func evaluate(
        _ body: String,
        background: String = #"{"service_worker": "worker.js"}"#,
        hasNativeDeclarativeNetRequest: Bool = true
    ) async throws -> [String: Any] {
        let script = """
            const extensionBaseURL = "webkit-extension://probe/";
            const declaredManifest = Object.freeze({manifest_version: 3, background: \(background)});
            const fallbackResourceURL = (path = "") => new URL(path, extensionBaseURL).href;
            const primaryRoot = {
                declarativeNetRequest: \(hasNativeDeclarativeNetRequest ? "{updateDynamicRules() {}}" : "undefined"),
                tabs: {
                    async get(id) { if (id !== 7) throw new Error('bad tab'); return {id, windowId: 12, index: 2}; },
                    async query() { return [{id: 7, windowId: 12, index: 2, url: 'https://example.com/'}]; }
                },
                windows: { async getCurrent() { return {id: 12, type: 'normal'}; } }
            };
            const nativeChrome = primaryRoot, nativeBrowser = primaryRoot;
            const brokerContexts = [
                {contextType: "BACKGROUND", contextId: "background-context",
                    documentOrigin: "webkit-extension://probe"},
                {contextType: "OFFSCREEN_DOCUMENT", contextId: "offscreen-context",
                    documentUrl: "webkit-extension://probe/offscreen.html",
                    documentOrigin: "webkit-extension://probe"},
                {contextType: "SIDE_PANEL", contextId: "panel-context", windowKind: "primary",
                    tabIndex: 2, tabURL: "https://example.com/",
                    documentUrl: "webkit-extension://probe/sidepanel.html?tabId=7",
                    documentOrigin: "webkit-extension://probe"},
                {contextType: "SIDE_PANEL", contextId: "global-panel-context", windowKind: "primary",
                    documentUrl: "webkit-extension://probe/sidepanel.html",
                    documentOrigin: "webkit-extension://probe"},
                {contextType: "NOT_A_TYPE", contextId: "ignored"}
            ];
            const requests = [];
            const requestCapability = async (api, payload, args, transform = value => value) => {
                requests.push({api, ...payload});
                const types = payload?.filter?.contextTypes;
                const contexts = Array.isArray(types)
                    ? brokerContexts.filter(context => types.includes(context.contextType))
                    : brokerContexts;
                return transform({contexts});
            };
            let lastErrorMessage;
            const invokeCallbackWithLastError = (callback, message) => {
                lastErrorMessage = message;
                callback(undefined);
            };
            const callbackOrPromise = (args, value) => {
                const callback = args.at(-1);
                if (typeof callback === "function") { queueMicrotask(() => callback(value)); return undefined; }
                return Promise.resolve(value);
            };
            const rejectCallbackOrPromise = (args, message) => {
                const callback = args.at(-1);
                if (typeof callback === "function") {
                    queueMicrotask(() => invokeCallbackWithLastError(callback, message));
                    return undefined;
                }
                return Promise.reject(new Error(message));
            };
            const presenceOnlyEvent = (path) => {
                const listeners = new Set();
                return Object.freeze({
                    addListener(listener) { if (typeof listener === "function") listeners.add(listener); },
                    removeListener(listener) { listeners.delete(listener); },
                    hasListener(listener) { return listeners.has(listener); },
                    hasListeners() { return listeners.size > 0; }
                });
            };
            const sidebarNative = async (namespace, method, ...args) => {
                const owner = primaryRoot[namespace];
                return Reflect.apply(owner[method], owner, args);
            };
            const sidebarPrimaryWindowId = async () => (await sidebarNative("windows", "getCurrent")).id;
            const sidebarTabIdFor = async (windowId, index, url) => {
                const tabs = await sidebarNative("tabs", "query", {windowId, index});
                const tab = tabs.find(tab => tab.index === index && (url === undefined || tab.url === url));
                if (!Number.isInteger(tab?.id)) throw new Error("The sidebar event's tab is no longer available.");
                return tab.id;
            };
            const runtime = {};
            const action = {};
            \(BrowserExtensionRuntimeContextsCompatibilityScript.source)
            \(BrowserExtensionDeclarativeNetRequestCompatibilityScript.source)
            return JSON.stringify(await (async () => { \(body) })());
            """
        let output = try await WKWebView().callAsyncJavaScript(script, arguments: [:], contentWorld: .page)
        let data = Data(try XCTUnwrap(output as? String).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
