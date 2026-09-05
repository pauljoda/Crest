/// Included inside the compatibility runtime's lexical scope, after the sidebar
/// fragment whose native-resolution helpers it reuses. The matrix owns
/// publication; defining these objects never makes an unavailable API visible.
///
/// `debugger` is a reserved word, so the namespace object is bound to
/// `debuggerNamespace` and published under its schema name by `fallbacksFor`.
enum BrowserExtensionDebuggerCompatibilityScript {
    static let source = #"""
        const debuggerDetachReason = Object.freeze({TARGET_CLOSED: "target_closed", CANCELED_BY_USER: "canceled_by_user"});
        const debuggerTargetInfoType = Object.freeze({PAGE: "page", BACKGROUND_PAGE: "background_page", WORKER: "worker", OTHER: "other"});
        // A session token is minted by Crest and bound to one native tab for
        // the life of the attachment. The tab index that resolved it is never
        // stored: a later command addresses the token, so reordering or
        // replacing tabs cannot redirect a live debugger session.
        const debuggerTokensByTab = new Map();
        const debuggerTabsByToken = new Map();
        const debuggerForget = (tabId) => {
            const token = debuggerTokensByTab.get(tabId);
            if (token !== undefined) debuggerTabsByToken.delete(token);
            debuggerTokensByTab.delete(tabId);
        };
        // Chrome reads `tabId` first and only then falls back to the other
        // debuggee shapes, so a target carrying both is a tab target.
        const debuggerTargetTabId = (target) => {
            if (!target || typeof target !== "object" || Array.isArray(target)) throw new Error("Either tab id or extension id must be specified.");
            if (target.tabId === undefined) {
                if (target.extensionId !== undefined || target.targetId !== undefined) throw new Error("Cannot attach to this target.");
                throw new Error("Either tab id or extension id must be specified.");
            }
            if (!Number.isInteger(target.tabId) || target.tabId < 0) throw new Error(`No tab with given id ${target.tabId}.`);
            return target.tabId;
        };
        const debuggerAttachedTabId = (target) => {
            const tabId = debuggerTargetTabId(target);
            if (!debuggerTokensByTab.has(tabId)) throw new Error(`Debugger is not attached to the tab with id: ${tabId}.`);
            return tabId;
        };
        const debuggerResolveTab = async (tabId) => {
            let tab;
            try { tab = await sidebarNative("tabs", "get", tabId); } catch { throw new Error(`No tab with given id ${tabId}.`); }
            if (!Number.isInteger(tab?.index) || tab.index < 0) throw new Error(`No tab with given id ${tabId}.`);
            return {tabIndex: tab.index, ...(typeof tab.url === "string" && tab.url.length > 0 ? {url: tab.url} : {})};
        };
        const debuggerTabsByIndex = async () => {
            let windowId;
            try { windowId = await sidebarPrimaryWindowId(); } catch {}
            let tabs = [];
            try { tabs = await sidebarNative("tabs", "query", windowId === undefined ? {} : {windowId}); } catch {}
            const byIndex = new Map();
            for (const tab of Array.isArray(tabs) ? tabs : []) {
                if (Number.isInteger(tab?.index) && Number.isInteger(tab?.id)) byIndex.set(tab.index, tab);
            }
            return byIndex;
        };
        const debuggerListeners = {event: new Set(), detach: new Set()};
        const debuggerListenerCount = () => debuggerListeners.event.size + debuggerListeners.detach.size;
        const debuggerWatch = capabilityWatch({
            api: "debugger",
            hasListeners: () => debuggerListenerCount() > 0,
            subscription: () => ({api: "debugger.watch"}),
            onMessage: message => {
                if (message?.api !== "debugger.event" || typeof message.sessionToken !== "string") return;
                const tabId = debuggerTabsByToken.get(message.sessionToken);
                if (tabId === undefined) return;
                const source = {tabId};
                if (message.kind === "detach") {
                    debuggerForget(tabId);
                    const reason = message.reason === debuggerDetachReason.CANCELED_BY_USER
                        ? debuggerDetachReason.CANCELED_BY_USER : debuggerDetachReason.TARGET_CLOSED;
                    for (const listener of debuggerListeners.detach) { try { listener(source, reason); } catch {} }
                    return;
                }
                if (message.kind !== "event" || typeof message.method !== "string") return;
                const params = message.params && typeof message.params === "object" && !Array.isArray(message.params)
                    ? message.params : undefined;
                for (const listener of debuggerListeners.event) { try { listener(source, message.method, params); } catch {} }
            }
        });
        const debuggerEvent = kind => Object.freeze({
            addListener(listener) {
                if (typeof listener !== "function") return;
                debuggerListeners[kind].add(listener);
                debuggerWatch.connect();
            },
            removeListener(listener) {
                debuggerListeners[kind].delete(listener);
                if (debuggerListenerCount() === 0) debuggerWatch.disconnect();
            },
            hasListener(listener) { return debuggerListeners[kind].has(listener); },
            hasListeners() { return debuggerListeners[kind].size > 0; }
        });
        const debuggerNamespace = {
            DetachReason: debuggerDetachReason,
            TargetInfoType: debuggerTargetInfoType,
            attach(...args) {
                let tabId;
                return sidebarCall("debugger.attach", args, async () => {
                    tabId = debuggerTargetTabId(args[0]);
                    const requiredVersion = args[1];
                    if (typeof requiredVersion !== "string") throw new Error(`Requested protocol version is not supported: ${requiredVersion}.`);
                    // Whether a debugger already holds the tab is Crest's
                    // answer, not this table's: the table can be stale, and
                    // another extension's session is not represented here at
                    // all.
                    return {...await debuggerResolveTab(tabId), tabId, requiredVersion};
                }, response => {
                    const sessionToken = response?.sessionToken;
                    if (typeof sessionToken !== "string" || sessionToken.length === 0) throw new Error("Cannot attach to this target.");
                    debuggerTokensByTab.set(tabId, sessionToken);
                    debuggerTabsByToken.set(sessionToken, tabId);
                    // Chrome delivers protocol events from the moment the
                    // attachment succeeds. A package that registered its
                    // listeners before attaching already connected the watch;
                    // this covers the reverse order.
                    debuggerWatch.connect();
                    return undefined;
                });
            },
            detach(...args) {
                let tabId;
                return sidebarCall("debugger.detach", args, () => {
                    tabId = debuggerAttachedTabId(args[0]);
                    return {sessionToken: debuggerTokensByTab.get(tabId)};
                }, () => {
                    // Chrome emits no onDetach for an explicit detach.
                    debuggerForget(tabId);
                    return undefined;
                }, error => {
                    debuggerForget(tabId);
                    return error;
                });
            },
            sendCommand(...args) {
                let tabId;
                return sidebarCall("debugger.sendCommand", args, () => {
                    tabId = debuggerAttachedTabId(args[0]);
                    const method = args[1];
                    if (typeof method !== "string" || method.length === 0) throw new Error("Invalid debugger request.");
                    const supplied = args[2];
                    const params = supplied && typeof supplied === "object" && !Array.isArray(supplied) ? supplied : undefined;
                    return {
                        sessionToken: debuggerTokensByTab.get(tabId), method,
                        ...(params === undefined ? {} : {params})
                    };
                }, response => {
                    const result = response?.result;
                    return result && typeof result === "object" && !Array.isArray(result) ? result : {};
                }, error => {
                    if (error?.message === "Detached while handling command.") debuggerForget(tabId);
                    return error;
                });
            },
            getTargets(...args) {
                return sidebarCall("debugger.getTargets", args, () => ({}), async response => {
                    const entries = Array.isArray(response?.targets) ? response.targets : [];
                    const byIndex = await debuggerTabsByIndex();
                    return entries.map(entry => {
                        const info = {
                            type: debuggerTargetInfoType.PAGE,
                            id: String(entry?.id ?? ""),
                            attached: entry?.attached === true,
                            title: typeof entry?.title === "string" ? entry.title : "",
                            url: typeof entry?.url === "string" ? entry.url : ""
                        };
                        const tab = byIndex.get(entry?.tabIndex);
                        if (tab !== undefined && (typeof tab.url !== "string" || typeof entry?.url !== "string" || tab.url === entry.url)) {
                            info.tabId = tab.id;
                        }
                        if (typeof entry?.faviconUrl === "string") info.faviconUrl = entry.faviconUrl;
                        return info;
                    });
                });
            },
            onEvent: debuggerEvent("event"),
            onDetach: debuggerEvent("detach")
        };
        """#
}
