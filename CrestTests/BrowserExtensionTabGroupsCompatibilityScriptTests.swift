import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionTabGroupsCompatibilityScriptTests: XCTestCase {
    func testMembershipNotificationsUseStableIdentityAndPreserveNativeListenerRemoval() async throws {
        let result = try await evaluate(
            """
            if (typeof tabGroupsObserveTabs !== 'function') return {available: false};
            const event = () => {
                const listeners = new Set();
                return {
                    addListener: fn => listeners.add(fn), removeListener: fn => listeners.delete(fn),
                    hasListener: fn => listeners.has(fn), hasListeners: () => listeners.size > 0,
                    emit: (...args) => { for (const fn of listeners) fn(...args); }
                };
            };
            primaryRoot.tabs.onUpdated = event();
            primaryRoot.tabs.onCreated = event();
            const nativeEvent = primaryRoot.tabs.onUpdated;
            tabGroupsObserveTabs(primaryRoot.tabs, tab => ({...tab, groupId: tab.groupId ?? tabGroupsProjectTab(tab)}));
            const received = [];
            const listener = (id, change, tab) => received.push({id, change, tab});
            primaryRoot.tabs.onUpdated.addListener(listener);
            await watches.tabMembership.onMessage({api: 'tabs.membership', windowKind: 'primary',
                changes: [{tabToken: 'fixture-seven', groupId: -1}]});
            // The event uses stable identity, not an old index from its payload.
            await watches.tabMembership.onMessage({api: 'tabs.membership', windowKind: 'primary',
                changes: [{tabToken: 'fixture-seven', groupId: 8}]});
            await watches.tabMembership.onMessage({api: 'tabs.membership', windowKind: 'auxiliary',
                changes: [{tabToken: 'fixture-seven', groupId: 99}]});
            const registered = primaryRoot.tabs.onUpdated.hasListener(listener);
            primaryRoot.tabs.onUpdated.removeListener(listener);
            await watches.tabMembership.onMessage({api: 'tabs.membership', windowKind: 'primary',
                changes: [{tabToken: 'fixture-seven', groupId: 9}]});
            return {available: true, received, registered, removed: !primaryRoot.tabs.onUpdated.hasListener(listener),
                identityPreserved: nativeEvent === primaryRoot.tabs.onUpdated,
                subscription: watches.tabMembership.subscription()};
            """)
        XCTAssertEqual(result["available"] as? Bool, true)
        XCTAssertEqual(result["registered"] as? Bool, true)
        XCTAssertEqual(result["removed"] as? Bool, true)
        XCTAssertEqual(result["identityPreserved"] as? Bool, true)
        XCTAssertEqual((result["subscription"] as? [String: String])?["api"], "tabs.watchMembership")
        let received = try XCTUnwrap(result["received"] as? [[String: Any]])
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.compactMap { $0["id"] as? Int }, [7, 7])
        XCTAssertEqual(received.compactMap { ($0["change"] as? [String: Any])?["groupId"] as? Int }, [-1, 8])
        XCTAssertEqual(received.compactMap { ($0["tab"] as? [String: Any])?["groupId"] as? Int }, [-1, 8])
    }

    func testNativeTabEventsIncludeGroupMetadataAndKeepTheirOtherFields() async throws {
        let result = try await evaluate(
            """
            let created, updated;
            const event = setter => ({
                addListener: setter, removeListener() {}, hasListener() {return true}, hasListeners() {return true}
            });
            primaryRoot.tabs.onCreated = event(fn => {created = fn});
            primaryRoot.tabs.onUpdated = event(fn => {updated = fn});
            tabGroupsObserveTabs(primaryRoot.tabs, tab => tab);
            const received = [];
            primaryRoot.tabs.onCreated.addListener(tab => received.push({kind:'created', tab}));
            primaryRoot.tabs.onUpdated.addListener((id, change, tab) => received.push({kind:'updated', id, change, tab}));
            created({id:7,index:999,windowId:12,title:'Native title'});
            updated(7,{status:'complete'},{id:7,index:999,windowId:12});
            await watches.tabMembership.onMessage({api:'tabs.membership',windowKind:'primary',changes:[]});
            return {received};
            """)
        let received = try XCTUnwrap(result["received"] as? [[String: Any]])
        XCTAssertEqual(received.count, 2)
        XCTAssertEqual(received.compactMap { ($0["tab"] as? [String: Any])?["groupId"] as? Int }, [4, 4])
        XCTAssertEqual((received.first?["tab"] as? [String: Any])?["title"] as? String, "Native title")
        XCTAssertEqual((received.last?["change"] as? [String: String])?["status"], "complete")
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
                "Invalid window ID: 99",
                "collapsed must be boolean.",
                "Missing required property 'index'.",
                "Missing required property 'tabIds'.",
                "No tab with id: 99.",
                "Cannot specify both 'groupId' and 'createProperties'.",
            ])
        XCTAssertTrue((result["requests"] as? [Any])?.isEmpty == true)
    }

    func testGroupingResolvesNativeTabIDsAndRefreshesMembership() async throws {
        let result = try await evaluate(
            """
            const before = tabGroupsProjectTab({index: 2});
            const groupId = await tabsGroup({tabIds: [7]});
            const after = tabGroupsProjectTab({index: 2});
            const ungroupResult = await tabsUngroup(7);
            return {before, groupId, after, ungroupResult, requests};
            """)
        // This direct mirror probe precedes any native tab read or grouping.
        XCTAssertEqual(result["before"] as? Int, -1)
        XCTAssertEqual(result["groupId"] as? Int, 4)
        XCTAssertEqual(result["after"] as? Int, 4)
        XCTAssertNil(result["ungroupResult"])

        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.map { $0["api"] as? String }, ["tabs.group", "tabs.ungroup"])
        // The wire carries no invented identifier: a numeric tab id becomes
        // the primary window's tab index plus the URL JavaScript saw.
        let targets = try XCTUnwrap(requests[0]["tabs"] as? [[String: Any]])
        XCTAssertEqual(targets.first?["tabIndex"] as? Int, 2)
        XCTAssertEqual(targets.first?["url"] as? String, "https://example.com/")
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
        _ body: String, declaredPermissions: [String] = [], nativeTabURL: String = "https://example.com/"
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
                        return {id, windowId: 12, index: 2, url: '\(nativeTabURL)'};
                    },
                    async query() { return [{id: 7, windowId: 12, index: 2, url: 'https://example.com/'}]; }
                },
                windows: { async getCurrent() { return {id: 12, type: 'normal'}; } }
            };
            const nativeChrome = primaryRoot, nativeBrowser = primaryRoot;
            const requests = [];
            let membershipSnapshot = {revision: 1, membership: [{tabIndex: 2, groupId: 4}], tabs: [{tabIndex: 2, tabToken: 'fixture-seven'}]};
            const group = {id: 4, collapsed: false, color: 'orange', title: 'Research', shared: false};
            const requestCapability = async (api, payload, args, transform = value => value) => {
                requests.push({api, ...payload});
                if (api === 'tabGroups.move') throw new Error('Failed to move group.');
                return transform(
                    api === 'tabGroups.query' ? {groups: [group]}
                    : api === 'tabs.group' ? {groupId: 4, membership: [{tabIndex: 2, groupId: 4}]}
                    : api === 'tabs.ungroup' ? {membership: []}
                    : api === 'tabGroups.membership' ? JSON.parse(JSON.stringify(membershipSnapshot))
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
