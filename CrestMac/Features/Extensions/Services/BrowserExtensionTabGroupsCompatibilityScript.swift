/// Included inside the compatibility runtime's lexical scope, after
/// `BrowserExtensionSidebarCompatibilityScript`, whose `sidebarNative`,
/// `sidebarPrimaryWindowId`, `sidebarDetails`, `sidebarProperty`, and
/// `sidebarCall` helpers this fragment reuses rather than re-deriving. The
/// matrix owns publication; defining these objects never makes an unavailable
/// API visible.
///
/// `normalizeTabsNamespace` is written earlier in the runtime and calls
/// `tabGroupsGroupTabs`, `tabGroupsUngroupTabs`, `tabGroupsQueryFilter`, and
/// `tabGroupsProjectTab` from here. It only ever *calls* them, and the call
/// happens once the whole runtime has been evaluated, so the temporal dead
/// zone is never entered.
enum BrowserExtensionTabGroupsCompatibilityScript {
    static let source = #"""
        const tabGroupsIdNone = -1;
        const tabGroupsColors = Object.freeze({
            GREY: "grey", BLUE: "blue", RED: "red", YELLOW: "yellow", GREEN: "green",
            PINK: "pink", PURPLE: "purple", CYAN: "cyan", ORANGE: "orange"
        });
        const tabGroupsColorValues = Object.freeze(Object.values(tabGroupsColors));
        const tabGroupsGroupId = (value) => {
            if (!Number.isInteger(value)) throw new Error("The tab group ID must be an integer.");
            return value;
        };
        // Chrome names the current window -2 and rejects any other id it does
        // not own. Crest presents one extension window per Space, so the only
        // acceptable answers are that Space's window and -2.
        const tabGroupsResolveWindow = async (id) => {
            const current = await sidebarPrimaryWindowId();
            if (id !== undefined && id !== -2 && id !== current) throw new Error(`No window with id: ${id}.`);
            return current;
        };
        // The broker names the window by kind, never by number: JavaScript
        // reads the id WebKit actually issued and stamps it here.
        const tabGroupsProject = (group, windowId) => {
            if (!group || typeof group !== "object" || !Number.isInteger(group.id)) return undefined;
            const projected = {
                id: group.id, collapsed: group.collapsed === true,
                color: typeof group.color === "string" ? group.color : tabGroupsColors.GREY,
                windowId, shared: group.shared === true
            };
            if (typeof group.title === "string") projected.title = group.title;
            return projected;
        };

        // `Tab.groupId` mirror.
        //
        // Chrome puts `groupId` on every tab object. Crest cannot: the field
        // lives in a Space-scoped registry the broker owns, and reading it
        // costs a native round trip that every `tabs.query` in every
        // extension would otherwise pay for a field most packages never look
        // at. So the mirror is switched on the moment a package shows it
        // cares — it declared `tabGroups`, it grouped or ungrouped a tab, or
        // it filtered a query by `groupId` — and until then every tab
        // truthfully reports `TAB_GROUP_ID_NONE`, which is what a package
        // that has created no group would see anyway. The deviation is that a
        // package which never asks will not observe a group some *other*
        // extension made.
        let tabGroupsProjectsMembership = declaredPermissionNames.has("tabGroups");
        let tabGroupsMembership = new Map();
        let tabGroupsMembershipRequest;
        const tabGroupsEnableProjection = () => { tabGroupsProjectsMembership = true; };
        const tabGroupsApplyMembership = (entries) => {
            const membership = new Map();
            for (const entry of Array.isArray(entries) ? entries : []) {
                if (Number.isInteger(entry?.tabIndex) && Number.isInteger(entry?.groupId)) {
                    membership.set(entry.tabIndex, entry.groupId);
                }
            }
            tabGroupsMembership = membership;
        };
        // Concurrent tab reads share one refresh instead of racing the broker.
        const tabGroupsSyncMembership = () => {
            if (!tabGroupsProjectsMembership) return undefined;
            if (tabGroupsMembershipRequest) return tabGroupsMembershipRequest;
            tabGroupsMembershipRequest = Promise.resolve()
                .then(() => requestCapability("tabGroups.membership", {}, [], (response) => {
                    tabGroupsApplyMembership(response?.membership);
                }))
                .catch(() => {})
                .finally(() => { tabGroupsMembershipRequest = undefined; });
            return tabGroupsMembershipRequest;
        };
        const tabGroupsProjectTab = (tab) => {
            if (!Number.isInteger(tab?.index)) return tabGroupsIdNone;
            const groupId = tabGroupsMembership.get(tab.index);
            return Number.isInteger(groupId) ? groupId : tabGroupsIdNone;
        };
        // Runs `invoke` once the mirror is current. Nothing to refresh means
        // nothing is deferred, so a package that never touches groups keeps
        // its `tabs.get`/`tabs.query` call synchronous and round-trip free.
        const tabGroupsWithMembership = (usesCallback, invoke) => {
            const sync = tabGroupsSyncMembership();
            if (!sync) return invoke();
            // The callback form returns nothing, so a deferred native throw
            // has nowhere to surface. Rethrow it on the task queue rather
            // than letting the refresh turn a loud argument error into a
            // silent unhandled rejection.
            if (usesCallback) {
                sync.then(invoke).catch((error) => {
                    globalThis.setTimeout(() => { throw error; }, 0);
                });
                return undefined;
            }
            return sync.then(invoke);
        };
        const tabGroupsQueryFilter = (options) => {
            if (!options || typeof options !== "object" || options.groupId === undefined) return undefined;
            if (!Number.isInteger(options.groupId)) throw new Error("The tab group ID must be an integer.");
            if (options.groupId !== tabGroupsIdNone) tabGroupsEnableProjection();
            return options.groupId;
        };

        const tabGroupsTabTarget = async (id) => {
            if (!Number.isInteger(id) || id < 0) throw new Error(`No tab with id: ${id}.`);
            let tab;
            try { tab = await sidebarNative("tabs", "get", id); } catch { throw new Error(`No tab with id: ${id}.`); }
            if (!Number.isInteger(tab?.index) || tab.index < 0) throw new Error(`No tab with id: ${id}.`);
            return {tabIndex: tab.index, ...(typeof tab.url === "string" ? {url: tab.url} : {})};
        };
        const tabGroupsTabTargets = async (value) => {
            const ids = Array.isArray(value) ? value : [value];
            if (ids.length === 0) throw new Error("No tabs given.");
            const targets = [];
            for (const id of ids) targets.push(await tabGroupsTabTarget(id));
            return targets;
        };
        const tabGroupsGroupTabs = (...args) => sidebarCall("tabs.group", args, async () => {
            const options = sidebarDetails(args);
            if (options.tabIds === undefined) throw new Error("Missing required property 'tabIds'.");
            const payload = {tabs: await tabGroupsTabTargets(options.tabIds)};
            if (options.groupId !== undefined) {
                if (options.createProperties !== undefined) throw new Error("Cannot specify both 'groupId' and 'createProperties'.");
                payload.groupId = tabGroupsGroupId(options.groupId);
            } else if (options.createProperties !== undefined) {
                const createProperties = options.createProperties;
                if (!createProperties || typeof createProperties !== "object" || Array.isArray(createProperties)) {
                    throw new Error("createProperties must be an object.");
                }
                if (createProperties.windowId !== undefined) await tabGroupsResolveWindow(createProperties.windowId);
            }
            return payload;
        }, (response) => {
            tabGroupsEnableProjection();
            tabGroupsApplyMembership(response?.membership);
            return response?.groupId;
        });
        const tabGroupsUngroupTabs = (...args) => sidebarCall("tabs.ungroup", args,
            async () => ({tabs: await tabGroupsTabTargets(args[0])}),
            (response) => {
                tabGroupsEnableProjection();
                tabGroupsApplyMembership(response?.membership);
                return undefined;
            });

        const tabGroupsListeners = {created: new Set(), updated: new Set(), removed: new Set()};
        const tabGroupsListenerCount = () =>
            tabGroupsListeners.created.size + tabGroupsListeners.updated.size + tabGroupsListeners.removed.size;
        let tabGroupsEventQueue = Promise.resolve();
        const tabGroupsWatch = capabilityWatch({
            api: "tabGroups",
            hasListeners: () => tabGroupsListenerCount() > 0,
            subscription: () => ({api: "tabGroups.watch"}),
            onMessage: (message) => {
                tabGroupsEventQueue = tabGroupsEventQueue.then(async () => {
                    if (message?.api !== "tabGroups.event" || message.windowKind !== "primary") return;
                    if (!tabGroupsListeners[message.kind]) return;
                    const group = tabGroupsProject(message.group, await sidebarPrimaryWindowId());
                    if (!group) return;
                    // The registry moved, so whatever the mirror holds is old.
                    tabGroupsMembership = new Map();
                    for (const listener of tabGroupsListeners[message.kind]) { try { listener(group); } catch {} }
                }).catch(() => {});
                return tabGroupsEventQueue;
            }
        });
        const tabGroupsEvent = (kind) => Object.freeze({
            addListener(listener) {
                if (typeof listener !== "function") return;
                tabGroupsListeners[kind].add(listener);
                tabGroupsWatch.connect();
            },
            removeListener(listener) {
                tabGroupsListeners[kind].delete(listener);
                if (tabGroupsListenerCount() === 0) tabGroupsWatch.disconnect();
            },
            hasListener(listener) { return tabGroupsListeners[kind].has(listener); },
            hasListeners() { return tabGroupsListeners[kind].size > 0; }
        });
        const tabGroups = {
            TAB_GROUP_ID_NONE: tabGroupsIdNone,
            Color: tabGroupsColors,
            get(...args) {
                let windowId;
                return sidebarCall("tabGroups.get", args, async () => {
                    const groupId = tabGroupsGroupId(args[0]);
                    windowId = await sidebarPrimaryWindowId();
                    return {groupId};
                }, (response) => tabGroupsProject(response?.group, windowId));
            },
            query(...args) {
                let windowId;
                return sidebarCall("tabGroups.query", args, async () => {
                    const options = sidebarDetails(args);
                    windowId = await tabGroupsResolveWindow(options.windowId);
                    const payload = {};
                    const collapsed = sidebarProperty(options, "collapsed", "boolean");
                    if (collapsed !== undefined) payload.collapsed = collapsed;
                    const shared = sidebarProperty(options, "shared", "boolean");
                    if (shared !== undefined) payload.shared = shared;
                    const title = sidebarProperty(options, "title", "string");
                    if (title !== undefined) payload.title = title;
                    const color = sidebarProperty(options, "color", "string");
                    if (color !== undefined) {
                        if (!tabGroupsColorValues.includes(color)) throw new Error(`Invalid enumeration value: ${color}`);
                        payload.color = color;
                    }
                    return payload;
                }, (response) => (Array.isArray(response?.groups) ? response.groups : [])
                    .map((group) => tabGroupsProject(group, windowId)).filter((group) => group !== undefined));
            },
            update(...args) {
                let windowId;
                return sidebarCall("tabGroups.update", args, async () => {
                    const groupId = tabGroupsGroupId(args[0]);
                    const options = sidebarDetails(args.slice(1));
                    const payload = {groupId};
                    const collapsed = sidebarProperty(options, "collapsed", "boolean");
                    if (collapsed !== undefined) payload.collapsed = collapsed;
                    const title = sidebarProperty(options, "title", "string");
                    if (title !== undefined) payload.title = title;
                    const color = sidebarProperty(options, "color", "string");
                    if (color !== undefined) {
                        if (!tabGroupsColorValues.includes(color)) throw new Error(`Invalid enumeration value: ${color}`);
                        payload.color = color;
                    }
                    windowId = await sidebarPrimaryWindowId();
                    return payload;
                }, (response) => tabGroupsProject(response?.group, windowId));
            },
            // Crest keeps group membership without reordering tabs, so there
            // is no position to move a group to. Chrome's own refusal text is
            // used rather than a Crest-flavoured one, and the broker still
            // validates the id first so a wrong id reports the wrong id.
            move(...args) {
                return sidebarCall("tabGroups.move", args, async () => {
                    const groupId = tabGroupsGroupId(args[0]);
                    const options = sidebarDetails(args.slice(1));
                    const index = sidebarProperty(options, "index", "number");
                    if (index === undefined) throw new Error("Missing required property 'index'.");
                    if (options.windowId !== undefined) await tabGroupsResolveWindow(options.windowId);
                    return {groupId, index};
                }, () => undefined);
            },
            onCreated: tabGroupsEvent("created"),
            onUpdated: tabGroupsEvent("updated"),
            onRemoved: tabGroupsEvent("removed")
        };
        """#
}
