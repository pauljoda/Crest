import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionTabGroupsCompatibilityScriptTests: XCTestCase {
    /// The official Claude extension reads `chrome.tabGroups.Color` in a
    /// static class field, so this shape is evaluated before its worker can
    /// do anything at all — including set its side-panel path.
    func testColorAndIdNoneMatchChromesSchemaAndAreFrozen() async throws {
        let result = try await evaluate(
            """
            const before = Object.assign({}, tabGroups.Color);
            try { tabGroups.Color.ORANGE = "chartreuse"; } catch {}
            try { tabGroups.Color.MAUVE = "mauve"; } catch {}
            return {
                surface: Object.keys(tabGroups).sort(),
                color: tabGroups.Color,
                keys: Object.keys(tabGroups.Color),
                frozen: Object.isFrozen(tabGroups.Color),
                unchanged: JSON.stringify(before) === JSON.stringify(tabGroups.Color),
                orange: tabGroups.Color.ORANGE,
                none: tabGroups.TAB_GROUP_ID_NONE,
                isMinusOne: tabGroups.TAB_GROUP_ID_NONE === -1
            };
            """)
        XCTAssertEqual(
            result["surface"] as? [String],
            [
                "Color", "TAB_GROUP_ID_NONE", "get", "move", "onCreated", "onRemoved", "onUpdated",
                "query", "update",
            ])
        XCTAssertEqual(
            result["keys"] as? [String],
            ["GREY", "BLUE", "RED", "YELLOW", "GREEN", "PINK", "PURPLE", "CYAN", "ORANGE"])
        XCTAssertEqual(
            result["color"] as? [String: String],
            [
                "GREY": "grey", "BLUE": "blue", "RED": "red", "YELLOW": "yellow", "GREEN": "green",
                "PINK": "pink", "PURPLE": "purple", "CYAN": "cyan", "ORANGE": "orange",
            ])
        XCTAssertEqual(result["frozen"] as? Bool, true)
        XCTAssertEqual(result["unchanged"] as? Bool, true)
        XCTAssertEqual(result["orange"] as? String, "orange")
        XCTAssertEqual(result["isMinusOne"] as? Bool, true)
    }

    func testGetQueryAndUpdateStampTheNativeWindowIdOntoTheBrokersGroup() async throws {
        let result = try await evaluate(
            """
            const fetched = await tabGroups.get(4);
            const queried = await tabGroups.query({color: 'orange', collapsed: false, title: 'Res*'});
            const updated = await tabGroups.update(4, {title: 'Research', color: 'orange'});
            const callbackGroup = await new Promise(resolve => tabGroups.get(4, resolve));
            return {fetched, queried, updated, callbackGroup, requests};
            """)
        let fetched = try XCTUnwrap(result["fetched"] as? [String: Any])
        XCTAssertEqual(fetched["id"] as? Int, 4)
        XCTAssertEqual(fetched["title"] as? String, "Research")
        XCTAssertEqual(fetched["color"] as? String, "orange")
        XCTAssertEqual(fetched["collapsed"] as? Bool, false)
        XCTAssertEqual(fetched["shared"] as? Bool, false)
        // The broker names the window by kind; the number comes from the
        // native `windows.getCurrent()`, exactly as the sidebar does it.
        XCTAssertEqual(fetched["windowId"] as? Int, 12)
        XCTAssertEqual((result["queried"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((result["updated"] as? [String: Any])?["id"] as? Int, 4)
        XCTAssertEqual((result["callbackGroup"] as? [String: Any])?["windowId"] as? Int, 12)

        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(
            requests.map { $0["api"] as? String },
            ["tabGroups.get", "tabGroups.query", "tabGroups.update", "tabGroups.get"])
        XCTAssertEqual(requests[1]["title"] as? String, "Res*")
        XCTAssertEqual(requests[1]["collapsed"] as? Bool, false)
        XCTAssertEqual(requests[2]["groupId"] as? Int, 4)
        XCTAssertEqual(requests[2]["title"] as? String, "Research")
    }

    func testMoveReachesTheBrokerAndRelaysChromesOwnRefusal() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            try { await tabGroups.move(4, {index: -1}); } catch (error) { errors.push(error.message); }
            const lastError = await new Promise(resolve => tabGroups.move(4, {index: 0}, () => resolve(lastErrorMessage)));
            return {errors, lastError, requests};
            """)
        XCTAssertEqual(result["errors"] as? [String], ["Failed to move group."])
        XCTAssertEqual(result["lastError"] as? String, "Failed to move group.")
        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0]["api"] as? String, "tabGroups.move")
        XCTAssertEqual(requests[0]["index"] as? Int, -1)
    }

    func testInvalidArgumentsAndForeignWindowsRejectBeforeTheBroker() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            for (const call of [
                () => tabGroups.get('4'),
                () => tabGroups.update(4, {color: 'chartreuse'}),
                () => tabGroups.query({windowId: 99}),
                () => tabGroups.query({collapsed: 'yes'}),
                () => tabGroups.move(4, {}),
                () => tabsGroup({}),
                () => tabsGroup({tabIds: 99}),
                () => tabsGroup({tabIds: 7, groupId: 4, createProperties: {}})
            ]) { try { await call(); } catch (error) { errors.push(error.message); } }
            return {errors, requests};
            """)
        XCTAssertEqual(
            result["errors"] as? [String],
            [
                "The tab group ID must be an integer.",
                "Invalid enumeration value: chartreuse",
                "No window with id: 99.",
                "collapsed must be boolean.",
                "Missing required property 'index'.",
                "Missing required property 'tabIds'.",
                "No tab with id: 99.",
                "Cannot specify both 'groupId' and 'createProperties'.",
            ])
        XCTAssertTrue((result["requests"] as? [Any])?.isEmpty == true)
    }

    func testGroupingResolvesNativeTabIDsAndTurnsOnTheGroupIdMirror() async throws {
        let result = try await evaluate(
            """
            const before = tabGroupsProjectTab({index: 2});
            const groupId = await tabsGroup({tabIds: [7]});
            const after = tabGroupsProjectTab({index: 2});
            const ungroupResult = await tabsUngroup(7);
            return {before, groupId, after, ungroupResult, requests, projects: tabGroupsProjectsMembership};
            """)
        // A package that has shown no interest in groups is told the truth it
        // would see in Chrome anyway: this tab is in no group.
        XCTAssertEqual(result["before"] as? Int, -1)
        XCTAssertEqual(result["groupId"] as? Int, 4)
        XCTAssertEqual(result["after"] as? Int, 4)
        XCTAssertEqual(result["projects"] as? Bool, true)
        XCTAssertNil(result["ungroupResult"])

        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.map { $0["api"] as? String }, ["tabs.group", "tabs.ungroup"])
        // The wire carries no invented identifier: a numeric tab id becomes
        // the primary window's tab index plus the URL JavaScript saw.
        let targets = try XCTUnwrap(requests[0]["tabs"] as? [[String: Any]])
        XCTAssertEqual(targets.first?["tabIndex"] as? Int, 2)
        XCTAssertEqual(targets.first?["url"] as? String, "https://example.com/")
    }

    func testTabQueryFilterEnablesProjectionAndTheMirrorRefreshesOnce() async throws {
        let result = try await evaluate(
            """
            const untouched = tabGroupsQueryFilter({active: true});
            const none = tabGroupsQueryFilter({groupId: -1});
            const offBefore = tabGroupsProjectsMembership;
            const requested = tabGroupsQueryFilter({groupId: 4});
            const on = tabGroupsProjectsMembership;
            // Concurrent tab reads must share one refresh, not race the broker.
            await Promise.all([tabGroupsWithMembership(false, () => 'a'), tabGroupsWithMembership(false, () => 'b')]);
            const projected = tabGroupsProjectTab({index: 2});
            return {untouched, none, offBefore, requested, on, projected, requests};
            """)
        XCTAssertNil(result["untouched"])
        XCTAssertEqual(result["none"] as? Int, -1)
        XCTAssertEqual(result["offBefore"] as? Bool, false)
        XCTAssertEqual(result["requested"] as? Int, 4)
        XCTAssertEqual(result["on"] as? Bool, true)
        XCTAssertEqual(result["projected"] as? Int, 4)
        XCTAssertEqual(
            (result["requests"] as? [[String: Any]])?.map { $0["api"] as? String },
            ["tabGroups.membership"])
    }

    func testDeclaringTabGroupsProjectsGroupIdWithoutAnyGroupingCall() async throws {
        let result = try await evaluate(
            """
            const off = tabGroupsWithMembership(false, () => 'sync');
            return {isPromise: typeof off?.then === 'function'};
            """, declaredPermissions: ["tabGroups"])
        XCTAssertEqual(result["isPromise"] as? Bool, true)
    }

    func testEventsUseTheirOwnWatchPortAndInvalidateTheMirror() async throws {
        let result = try await evaluate(
            """
            const received = [];
            tabGroups.onCreated.addListener(group => received.push(['created', group]));
            tabGroups.onUpdated.addListener(group => received.push(['updated', group]));
            tabGroups.onRemoved.addListener(group => received.push(['removed', group]));
            tabGroupsApplyMembership([{tabIndex: 2, groupId: 4}]);
            const beforeEvent = tabGroupsProjectTab({index: 2});
            await watches.tabGroups.onMessage({api: 'tabGroups.event', kind: 'created', windowKind: 'primary',
                group: {id: 4, collapsed: false, color: 'orange', title: 'Research', shared: false}});
            await watches.tabGroups.onMessage({api: 'tabGroups.event', kind: 'removed', windowKind: 'primary',
                group: {id: 4, collapsed: false, color: 'orange', shared: false}});
            // Neither an auxiliary window nor another watch's traffic is ours.
            await watches.tabGroups.onMessage({api: 'tabGroups.event', kind: 'created', windowKind: 'auxiliary', group: {id: 9}});
            await watches.tabGroups.onMessage({api: 'sidebar.event', kind: 'created', windowKind: 'primary', group: {id: 9}});
            return {received, beforeEvent, afterEvent: tabGroupsProjectTab({index: 2}),
                subscription: watches.tabGroups.subscription(), connections};
            """)
        XCTAssertEqual(result["beforeEvent"] as? Int, 4)
        // The registry moved, so the mirror is stale and must be dropped.
        XCTAssertEqual(result["afterEvent"] as? Int, -1)
        XCTAssertEqual((result["subscription"] as? [String: String])?["api"], "tabGroups.watch")
        XCTAssertEqual(result["connections"] as? Int, 3)

        let received = try XCTUnwrap(result["received"] as? [[Any]])
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received[0][0] as? String, "created")
        let created = try XCTUnwrap(received[0][1] as? [String: Any])
        XCTAssertEqual(created["id"] as? Int, 4)
        XCTAssertEqual(created["title"] as? String, "Research")
        XCTAssertEqual(created["windowId"] as? Int, 12)
        XCTAssertEqual(received[1][0] as? String, "removed")
        // Chrome omits `title` entirely for an untitled group.
        XCTAssertNil((received[1][1] as? [String: Any])?["title"])
    }

    private func evaluate(
        _ body: String, declaredPermissions: [String] = []
    ) async throws -> [String: Any] {
        let permissions = declaredPermissions.map { "\"\($0)\"" }.joined(separator: ", ")
        let script = """
            let activation = false;
            Object.defineProperty(globalThis.navigator, 'userActivation', {configurable: true, get: () => ({isActive: activation})});
            const declaredPermissionNames = new Set([\(permissions)]);
            const primaryRoot = {
                tabs: {
                    async get(id) {
                        if (id !== 7) throw new Error('bad tab');
                        return {id, windowId: 12, index: 2, url: 'https://example.com/'};
                    },
                    async query() { return [{id: 7, windowId: 12, index: 2, url: 'https://example.com/'}]; }
                },
                windows: { async getCurrent() { return {id: 12, type: 'normal'}; } }
            };
            const nativeChrome = primaryRoot, nativeBrowser = primaryRoot;
            const requests = [];
            const group = {id: 4, collapsed: false, color: 'orange', title: 'Research', shared: false};
            const requestCapability = async (api, payload, args, transform = value => value) => {
                requests.push({api, ...payload});
                if (api === 'tabGroups.move') throw new Error('Failed to move group.');
                return transform(
                    api === 'tabGroups.query' ? {groups: [group]}
                    : api === 'tabs.group' ? {groupId: 4, membership: [{tabIndex: 2, groupId: 4}]}
                    : api === 'tabs.ungroup' ? {membership: []}
                    : api === 'tabGroups.membership' ? {membership: [{tabIndex: 2, groupId: 4}]}
                    : {group});
            };
            let lastErrorMessage;
            const invokeCallbackWithLastError = (callback, message) => { lastErrorMessage = message; callback(undefined); };
            const watches = {}; let connections = 0;
            const capabilityWatch = options => {
                watches[options.api] = options;
                return {connect() { connections++; }, disconnect() {}, resubscribe() {}};
            };
            \(BrowserExtensionSidebarCompatibilityScript.source)
            \(BrowserExtensionTabGroupsCompatibilityScript.source)
            const tabsGroup = tabGroupsGroupTabs;
            const tabsUngroup = tabGroupsUngroupTabs;
            return JSON.stringify(await (async () => { \(body) })());
            """
        let output = try await WKWebView().callAsyncJavaScript(
            script, arguments: [:], contentWorld: .page)
        let data = Data(try XCTUnwrap(output as? String).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
