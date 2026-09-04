/// Included inside the compatibility runtime's lexical scope. The matrix owns
/// publication; defining these objects never makes an unavailable API visible.
enum BrowserExtensionSidebarCompatibilityScript {
    static let source = #"""
        const sidebarDetails = (args) => {
            const value = args[0];
            if (value === undefined || typeof value === "function") return {};
            if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Sidebar options must be an object.");
            return value;
        };
        const sidebarProperty = (options, name, type, nullable = false) => {
            if (options[name] === undefined) return undefined;
            if (nullable && options[name] === null) return null;
            if (typeof options[name] !== type) throw new Error(`${name} must be ${type}.`);
            return options[name];
        };
        const sidebarCall = (api, args, payload, transform = value => value, errorTransform = error => error) => {
            const response = Promise.resolve().then(payload).then(value => requestCapability(api, value, [], transform))
                .catch(error => { throw errorTransform(error); });
            const callback = args.at(-1);
            if (typeof callback !== "function") return response;
            response.then(value => callback(value), error => invokeCallbackWithLastError(callback, error?.message ?? `${api} failed.`));
            return undefined;
        };
        const sidebarNative = async (namespace, method, ...args) => {
            for (const root of [globalThis.browser, globalThis.chrome, primaryRoot, nativeBrowser, nativeChrome]) {
                let owner;
                try { owner = root?.[namespace]; } catch {}
                if (typeof owner?.[method] === "function") return Reflect.apply(owner[method], owner, args);
            }
            throw new Error(`Crest cannot resolve the sidebar's ${namespace} target.`);
        };
        const sidebarPrimaryWindowId = async () => {
            const window = await sidebarNative("windows", "getCurrent");
            if (!Number.isInteger(window?.id) || (window.type && window.type !== "normal")) throw new Error("The extension side panel requires a regular browser window.");
            return window.id;
        };
        const sidebarResolveWindow = async (id) => {
            if (id !== undefined && (!Number.isInteger(id) || (id < 0 && id !== -2))) throw new Error(`Invalid window ID: ${id}`);
            const current = await sidebarPrimaryWindowId();
            if (id !== undefined && id !== -2 && id !== current) throw new Error(`Invalid window ID: ${id}`);
            return {windowKind: "primary"};
        };
        const sidebarResolveTab = async (id, windowId) => {
            if (!Number.isInteger(id) || id < 0) throw new Error(`Invalid tab ID: ${id}`);
            let tab;
            try { tab = await sidebarNative("tabs", "get", id); }
            catch { throw new Error(`Invalid tab ID: ${id}`); }
            if (windowId !== undefined && windowId !== -2 && windowId !== tab?.windowId) throw new Error("The specified tab does not belong to the specified window.");
            await sidebarResolveWindow(windowId ?? tab?.windowId);
            if (!Number.isInteger(tab?.index) || tab.index < 0) throw new Error(`Invalid tab ID: ${id}`);
            return {windowKind: "primary", tabIndex: tab.index, ...(typeof tab.url === "string" ? {url: tab.url} : {})};
        };
        const sidebarScope = async (options, firefox = false) => {
            if (firefox && options.tabId !== undefined && options.windowId !== undefined) throw new Error("Only one of tabId and windowId can be specified.");
            if (options.tabId !== undefined) return {kind: "tab", ...await sidebarResolveTab(options.tabId)};
            if (firefox && options.windowId !== undefined) return {kind: "window", ...await sidebarResolveWindow(options.windowId)};
            return {kind: "default"};
        };
        // Capture activation before tabs.get/windows.getCurrent can yield.
        const sidebarUserActivation = () => globalThis.navigator?.userActivation?.isActive === true;
        const sidebarChromeTarget = async (options) => {
            if (options.tabId === undefined && options.windowId === undefined) throw new Error("At least one of `tabId` and `windowId` must be provided");
            return options.tabId !== undefined ? sidebarResolveTab(options.tabId, options.windowId) : sidebarResolveWindow(options.windowId);
        };
        const sidebarChromeAction = (api, args, userActivation) => {
            let options;
            return sidebarCall(api, args, async () => {
                options = sidebarDetails(args);
                return {...await sidebarChromeTarget(options), userActivation};
            }, () => undefined, error => {
                if (error?.message?.includes("No active tab-specific side panel.")) return new Error(`No active tab-specific side panel for tabId: ${options?.tabId}`);
                if (error?.message?.includes("No active side panel.")) {
                    return new Error(options?.tabId !== undefined ? `No active side panel for tabId: ${options.tabId}` : `No active side panel for windowId: ${options?.windowId}`);
                }
                return error;
            });
        };
        const sidebarTabIdFor = async (windowId, index, url) => {
            const tabs = await sidebarNative("tabs", "query", {windowId, index});
            const tab = tabs.find(tab => tab.index === index && (url === undefined || tab.url === url));
            if (!Number.isInteger(tab?.id)) throw new Error("The sidebar event's tab is no longer available.");
            return tab.id;
        };
        const sidebarListeners = {opened: new Set(), closed: new Set()};
        const sidebarListenerCount = () => sidebarListeners.opened.size + sidebarListeners.closed.size;
        let sidebarEventQueue = Promise.resolve();
        const sidebarWatch = capabilityWatch({
            api: "sidebar",
            hasListeners: () => sidebarListenerCount() > 0,
            subscription: () => ({api: "sidebar.watch"}),
            onMessage: message => {
                sidebarEventQueue = sidebarEventQueue.then(async () => {
                    if (message?.api !== "sidebar.event" || message.windowKind !== "primary" || typeof message.path !== "string" || !sidebarListeners[message.kind]) return;
                    const windowId = await sidebarPrimaryWindowId();
                    const info = {windowId, path: message.path};
                    if (message.tabIndex !== undefined) info.tabId = await sidebarTabIdFor(windowId, message.tabIndex, message.url);
                    for (const listener of sidebarListeners[message.kind]) { try { listener(info); } catch {} }
                }).catch(() => {});
                return sidebarEventQueue;
            }
        });
        const sidebarEvent = kind => Object.freeze({
            addListener(listener) {
                if (typeof listener !== "function") return;
                sidebarListeners[kind].add(listener);
                sidebarWatch.connect();
            },
            removeListener(listener) {
                sidebarListeners[kind].delete(listener);
                if (sidebarListenerCount() === 0) sidebarWatch.disconnect();
            },
            hasListener(listener) { return sidebarListeners[kind].has(listener); },
            hasListeners() { return sidebarListeners[kind].size > 0; }
        });
        const sidePanel = {
            Side: Object.freeze({LEFT: "left", RIGHT: "right"}),
            setOptions(...args) {
                return sidebarCall("sidePanel.setOptions", args, async () => {
                    const options = sidebarDetails(args);
                    const path = sidebarProperty(options, "path", "string");
                    const enabled = sidebarProperty(options, "enabled", "boolean");
                    return {scope: await sidebarScope(options), ...(path === undefined ? {} : {path}), ...(enabled === undefined ? {} : {enabled})};
                }, () => undefined);
            },
            getOptions(...args) {
                let options;
                return sidebarCall("sidePanel.getOptions", args, async () => {
                    options = sidebarDetails(args);
                    return {scope: await sidebarScope(options)};
                }, response => {
                    const result = {};
                    if (response.path !== undefined) result.path = response.path;
                    if (response.enabled !== undefined) result.enabled = response.enabled;
                    if (response.tabSpecific === true) result.tabId = options.tabId;
                    return result;
                });
            },
            setPanelBehavior(...args) {
                return sidebarCall("sidePanel.setPanelBehavior", args, () => {
                    const value = sidebarProperty(sidebarDetails(args), "openPanelOnActionClick", "boolean");
                    return value === undefined ? {} : {openPanelOnActionClick: value};
                }, () => undefined);
            },
            getPanelBehavior(...args) {
                return sidebarCall("sidePanel.getPanelBehavior", args, () => ({}), response => ({openPanelOnActionClick: response.openPanelOnActionClick === true}));
            },
            open(...args) { return sidebarChromeAction("sidePanel.open", args, sidebarUserActivation()); },
            close(...args) { return sidebarChromeAction("sidePanel.close", args, false); },
            getLayout(...args) { return sidebarCall("sidebar.layout", args, () => ({}), response => ({side: response.side})); },
            onOpened: sidebarEvent("opened"),
            onClosed: sidebarEvent("closed")
        };
        const sidebarFirefoxAction = (api, args, userActivation) => sidebarCall(api, args,
            async () => ({...await sidebarResolveWindow(), userActivation}), () => undefined);
        const sidebarAction = {
            setTitle(...args) {
                return sidebarCall("sidebarAction.setTitle", args, async () => {
                    const options = sidebarDetails(args);
                    const title = sidebarProperty(options, "title", "string", true);
                    if (title === undefined) throw new Error("title is required.");
                    return {scope: await sidebarScope(options, true), title};
                }, () => undefined);
            },
            getTitle(...args) {
                return sidebarCall("sidebarAction.getTitle", args, async () => ({scope: await sidebarScope(sidebarDetails(args), true)}), response => response.title);
            },
            setPanel(...args) {
                return sidebarCall("sidebarAction.setPanel", args, async () => {
                    const options = sidebarDetails(args);
                    const panel = sidebarProperty(options, "panel", "string", true);
                    if (panel === undefined) throw new Error("panel is required.");
                    return {scope: await sidebarScope(options, true), panel};
                }, () => undefined);
            },
            getPanel(...args) {
                return sidebarCall("sidebarAction.getPanel", args, async () => ({scope: await sidebarScope(sidebarDetails(args), true)}), response => response.panel);
            },
            setIcon(...args) {
                return sidebarCall("sidebarAction.setIcon", args, async () => {
                    const options = sidebarDetails(args);
                    if (options.imageData !== undefined) throw new Error("sidebarAction.setIcon: Crest supports path icons only.");
                    let path = options.path;
                    if (path && typeof path === "object" && !Array.isArray(path)) {
                        const sizes = Object.keys(path).map(Number).filter(size => Number.isFinite(size) && size > 0).sort((a, b) => a - b);
                        const size = sizes.find(size => size >= 32) ?? sizes.at(-1);
                        path = size === undefined ? undefined : path[size];
                    }
                    if (path !== undefined && typeof path !== "string") throw new Error("path must be a string or icon-size dictionary.");
                    return {scope: await sidebarScope(options, true), ...(path === undefined ? {} : {path})};
                }, () => undefined);
            },
            open(...args) { return sidebarFirefoxAction("sidebarAction.open", args, sidebarUserActivation()); },
            close(...args) { return sidebarFirefoxAction("sidebarAction.close", args, sidebarUserActivation()); },
            toggle(...args) { return sidebarFirefoxAction("sidebarAction.toggle", args, sidebarUserActivation()); },
            isOpen(...args) {
                return sidebarCall("sidebarAction.isOpen", args, async () => sidebarResolveWindow(sidebarDetails(args).windowId), response => response.isOpen === true);
            }
        };
        """#
}
