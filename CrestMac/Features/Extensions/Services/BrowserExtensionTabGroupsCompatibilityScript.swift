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
        // Membership is ordinary tab metadata, including folders created by
        // the user or another extension. It does not require `tabs` or
        // `tabGroups`; WebKit still owns sensitive URL/title filtering.
        let tabGroupsMembership = new Map();
        let tabGroupsMembershipRequest;
        let tabGroupsPrimaryWindow;
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
            if (tabGroupsMembershipRequest) return tabGroupsMembershipRequest;
            tabGroupsMembershipRequest = Promise.resolve()
                .then(async () => {
                    const [response, windowId] = await Promise.all([
                        requestCapability("tabGroups.membership", {}, []),
                        tabGroupsPrimaryWindow ?? sidebarPrimaryWindowId()
                    ]);
                    tabGroupsPrimaryWindow = windowId;
                    tabGroupsApplyMembership(response?.membership);
                })
                .catch(() => {})
                .finally(() => { tabGroupsMembershipRequest = undefined; });
            return tabGroupsMembershipRequest;
        };
        const tabGroupsProjectTab = (tab) => {
            if (!Number.isInteger(tab?.index)) return tabGroupsIdNone;
            if (Number.isInteger(tab.windowId) && tab.windowId !== tabGroupsPrimaryWindow) return tabGroupsIdNone;
            const groupId = tabGroupsMembership.get(tab.index);
            return Number.isInteger(groupId) ? groupId : tabGroupsIdNone;
        };
        // Runs the native tab read once the Space's membership is current.
        // Concurrent calls share a refresh, including callback-style callers.
        const tabGroupsWithMembership = (usesCallback, invoke) => {
            const sync = tabGroupsSyncMembership();
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
            return options.groupId;
        };

        const tabGroupsTabTarget = async (id) => {
            if (!Number.isInteger(id) || id < 0) throw new Error(`No tab with id: ${id}.`);
            let tab;
            try { tab = await sidebarNative("tabs", "get", id); } catch { throw new Error(`No tab with id: ${id}.`); }
            if (!Number.isInteger(tab?.index) || tab.index < 0) throw new Error(`No tab with id: ${id}.`);
            if (Number.isInteger(tab.windowId) && tab.windowId !== await sidebarPrimaryWindowId()) {
                throw new Error(`No tab with id: ${id}.`);
            }
            // WebKit returns an empty string when the URL is withheld, including
            // browser-owned new tabs. There is no URL identity to compare then.
            return {tabIndex: tab.index, ...(typeof tab.url === "string" && tab.url.length > 0 ? {url: tab.url} : {})};
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
            tabGroupsApplyMembership(response?.membership);
            return response?.groupId;
        });
        const tabGroupsUngroupTabs = (...args) => sidebarCall("tabs.ungroup", args,
            async () => ({tabs: await tabGroupsTabTargets(args[0])}),
            (response) => {
                tabGroupsApplyMembership(response?.membership);
                return undefined;
            });

        const tabGroupsMoveTabs = (...args) => {
            let ids;
            return sidebarCall("tabs.move", args, async () => {
                const options = sidebarDetails(args.slice(1));
                if (!Number.isInteger(options.index) || options.index < -1 || options.index > 2147483647) {
                    throw new Error("The tab index must be an integer greater than or equal to -1.");
                }
                await tabGroupsResolveWindow(options.windowId);
                ids = Array.isArray(args[0]) ? args[0].slice() : [args[0]];
                return {index: options.index, tabs: await tabGroupsTabTargets(ids)};
            }, async () => {
                // Return WebKit's actual post-move values, including its own
                // URL/title access checks. A single result is a Tab even when
                // the caller supplied a one-element array.
                await tabGroupsSyncMembership();
                const tabs = await Promise.all(ids.map(id => sidebarNative("tabs", "get", id)));
                return tabs.length === 1 ? tabs[0] : tabs;
            });
        };

        // Event correlation is by an opaque session token, never by an old
        // row index. Verify the host revision around the native query before
        // pairing tokens with WebKit IDs; this also catches move-away-and-back.
        const tabGroupsObserveTabs = (nativeTabs, normalizeTab) => {
            const nativeQuery = nativeTabs.query;
            const nativeGet = nativeTabs.get;
            if (typeof nativeQuery !== "function" || typeof nativeGet !== "function") return;
            const idsByToken = new Map();
            const tokensById = new Map();
            let queue = Promise.resolve();
            const enqueue = work => {
                const result = queue.then(work);
                queue = result.catch(() => {});
                return result;
            };
            const snapshot = () => requestCapability("tabGroups.membership", {}, []);
            const identityKey = value => JSON.stringify([
                value?.revision,
                (value?.tabs ?? []).map(tab => [tab.tabToken, tab.tabIndex])
            ]);
            const resolveIdentity = async () => {
                const windowId = await sidebarPrimaryWindowId();
                tabGroupsPrimaryWindow = windowId;
                for (let attempt = 0; attempt < 4; attempt++) {
                    const before = await snapshot();
                    const tabs = await Reflect.apply(nativeQuery, nativeTabs, [{windowId}]);
                    const after = await snapshot();
                    if (identityKey(before) !== identityKey(after)) continue;
                    if (!Array.isArray(after?.tabs) || !Array.isArray(tabs)) return false;
                    const native = tabs.filter(tab => tab.windowId === windowId);
                    const indexed = new Map(native.map(tab => [tab.index, tab]));
                    if (native.length !== after.tabs.length || indexed.size !== native.length
                        || after.tabs.some(tab => typeof tab.tabToken !== "string"
                            || !Number.isInteger(indexed.get(tab.tabIndex)?.id))) continue;
                    // Bound correlation to currently live tabs. Queued events
                    // for a closed tab can no longer deliver a native Tab.
                    idsByToken.clear();
                    tokensById.clear();
                    for (const tab of after.tabs) {
                        const id = indexed.get(tab.tabIndex).id;
                        idsByToken.set(tab.tabToken, id);
                        tokensById.set(id, tab.tabToken);
                    }
                    tabGroupsApplyMembership(after.membership);
                    return true;
                }
                throw new Error("Tab order changed while resolving extension event identities.");
            };
            const updatedListeners = new Set();
            const watch = capabilityWatch({
                api: "tabMembership",
                hasListeners: () => updatedListeners.size > 0,
                subscription: () => ({api: "tabs.watchMembership"}),
                onMessage: message => {
                    if (message?.api !== "tabs.membership" || message.windowKind !== "primary") return queue;
                    const listeners = [...updatedListeners];
                    return enqueue(async () => {
                        const changes = (Array.isArray(message.changes) ? message.changes : [])
                            .filter(change => typeof change?.tabToken === "string" && Number.isInteger(change.groupId));
                        if (changes.some(change => !idsByToken.has(change.tabToken))) await resolveIdentity();
                        for (const change of changes) {
                            const id = idsByToken.get(change.tabToken);
                            if (!Number.isInteger(id)) continue;
                            let tab;
                            try { tab = await Reflect.apply(nativeGet, nativeTabs, [id]); } catch { continue; }
                            if (!tab || tab.windowId !== tabGroupsPrimaryWindow) continue;
                            const projected = normalizeTab({...tab, groupId: change.groupId});
                            for (const listener of listeners) {
                                if (!updatedListeners.has(listener)) continue;
                                try { listener(id, {groupId: change.groupId}, projected); } catch {}
                            }
                        }
                    });
                }
            });
            const projectEventTab = async tab => {
                if (!tab || typeof tab !== "object") return tab;
                if (!tokensById.has(tab.id)) await resolveIdentity();
                const token = tokensById.get(tab.id);
                const current = await snapshot();
                tabGroupsApplyMembership(current?.membership);
                const identity = current?.tabs?.find(value => value.tabToken === token);
                const groupId = identity ? tabGroupsProjectTab({index: identity.tabIndex, windowId: tab.windowId}) : -1;
                return normalizeTab({...tab, groupId});
            };
            for (const name of ["onCreated", "onUpdated"]) {
                const event = nativeTabs[name];
                if (typeof event?.addListener !== "function") continue;
                const add = event.addListener, remove = event.removeListener;
                const has = event.hasListener, any = event.hasListeners;
                const listeners = name === "onUpdated" ? updatedListeners : new Set();
                const dispatch = (...args) => {
                    const recipients = [...listeners];
                    void enqueue(async () => {
                        const index = name === "onCreated" ? 0 : 2;
                        // Preserve the native event even if the metadata
                        // service is temporarily unavailable.
                        try { args[index] = await projectEventTab(args[index]); } catch {}
                        for (const listener of recipients) {
                            if (!listeners.has(listener)) continue;
                            try { listener(...args); } catch {}
                        }
                    });
                };
                Object.defineProperties(event, {
                    addListener: {configurable: true, value(listener, ...args) {
                        if (typeof listener !== "function") return Reflect.apply(add, event, [listener, ...args]);
                        if (listeners.has(listener)) return;
                        const firstListener = listeners.size === 0;
                        if (firstListener) Reflect.apply(add, event, [dispatch, ...args]);
                        listeners.add(listener);
                        if (name === "onUpdated") {
                            watch.connect();
                            // Seed correlation before the first regroup. This
                            // is metadata-only and never grants tab access.
                            if (firstListener) void enqueue(resolveIdentity).catch(() => {});
                        }
                    }},
                    removeListener: {configurable: true, value(listener) {
                        if (!listeners.delete(listener)) return Reflect.apply(remove, event, [listener]);
                        if (listeners.size === 0) Reflect.apply(remove, event, [dispatch]);
                        if (name === "onUpdated" && listeners.size === 0) watch.disconnect();
                    }},
                    hasListener: {configurable: true, value(listener) {
                        return listeners.has(listener) || Reflect.apply(has, event, [listener]);
                    }},
                    hasListeners: {configurable: true, value() {
                        return listeners.size > 0 || Reflect.apply(any, event, []);
                    }}
                });
            }
        };

        const tabGroupsListeners = {created: new Set(), updated: new Set(), removed: new Set(), moved: new Set()};
        const tabGroupsListenerCount = () =>
            Object.values(tabGroupsListeners).reduce((count, listeners) => count + listeners.size, 0);
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
            move(...args) {
                let windowId;
                return sidebarCall("tabGroups.move", args, async () => {
                    const groupId = tabGroupsGroupId(args[0]);
                    const options = sidebarDetails(args.slice(1));
                    const index = sidebarProperty(options, "index", "number");
                    if (index === undefined) throw new Error("Missing required property 'index'.");
                    if (index < -1) throw new Error("Invalid tab group index.");
                    if (options.windowId !== undefined) await tabGroupsResolveWindow(options.windowId);
                    windowId = await sidebarPrimaryWindowId();
                    return {groupId, index};
                }, (response) => tabGroupsProject(response?.group, windowId));
            },
            onCreated: tabGroupsEvent("created"),
            onUpdated: tabGroupsEvent("updated"),
            onMoved: tabGroupsEvent("moved"),
            onRemoved: tabGroupsEvent("removed")
        };
        """#
}
