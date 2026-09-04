/// Included inside the compatibility runtime's lexical scope, after the
/// `runtime` and `action` fallback objects and after the sidebar fragment
/// whose tab and window resolvers it reuses. The matrix owns publication;
/// defining these members never makes an unavailable API visible.
///
/// WebKit's `WebExtensionAPIRuntime.idl` publishes no `getContexts` and none
/// of Chrome's `runtime` enums, and its action IDL publishes neither
/// `setBadgeTextColor` nor `onUserSettingsChanged`. Portable packages
/// dereference all of them unguarded — Claude's side-panel toggle reads
/// `chrome.runtime.ContextType.SIDE_PANEL` and awaits
/// `chrome.runtime.getContexts`, and its install handler compares against
/// `chrome.runtime.OnInstalledReason.INSTALL` — so an absent enum throws
/// inside whatever awaited it and takes the rest of that bootstrap with it.
enum BrowserExtensionRuntimeContextsCompatibilityScript {
    static let source = #"""
        // Chrome's runtime enums, member for member from the pinned
        // `runtime.json`. Keys are Chrome's generated UPPER_SNAKE spelling of
        // each schema value; `ContextType` is the one whose values are already
        // upper case in the schema itself.
        const runtimeContextTypes = Object.freeze({
            TAB: "TAB",
            POPUP: "POPUP",
            BACKGROUND: "BACKGROUND",
            OFFSCREEN_DOCUMENT: "OFFSCREEN_DOCUMENT",
            SIDE_PANEL: "SIDE_PANEL",
            DEVELOPER_TOOLS: "DEVELOPER_TOOLS"
        });
        const runtimeSchemaEnums = {
            ContextType: runtimeContextTypes,
            OnInstalledReason: Object.freeze({
                INSTALL: "install",
                UPDATE: "update",
                CHROME_UPDATE: "chrome_update",
                SHARED_MODULE_UPDATE: "shared_module_update"
            }),
            OnRestartRequiredReason: Object.freeze({
                APP_UPDATE: "app_update",
                OS_UPDATE: "os_update",
                PERIODIC: "periodic"
            }),
            PlatformArch: Object.freeze({
                ARM: "arm",
                ARM64: "arm64",
                X86_32: "x86-32",
                X86_64: "x86-64",
                MIPS: "mips",
                MIPS64: "mips64",
                RISCV64: "riscv64"
            }),
            PlatformNaclArch: Object.freeze({
                ARM: "arm",
                X86_32: "x86-32",
                X86_64: "x86-64",
                MIPS: "mips",
                MIPS64: "mips64"
            }),
            PlatformOs: Object.freeze({
                MAC: "mac",
                WIN: "win",
                ANDROID: "android",
                CROS: "cros",
                LINUX: "linux",
                OPENBSD: "openbsd"
            }),
            RequestUpdateCheckStatus: Object.freeze({
                THROTTLED: "throttled",
                NO_UPDATE: "no_update",
                UPDATE_AVAILABLE: "update_available"
            })
        };
        const runtimeContextFilterArrays = Object.freeze([
            "contextIds",
            "contextTypes",
            "documentIds",
            "documentOrigins",
            "documentUrls",
            "frameIds",
            "tabIds",
            "windowIds"
        ]);
        // Chrome's ContextFilter is an AND across the fields present and an OR
        // within each array; an absent field matches everything. Validate the
        // shape before the broker sees it so a malformed filter fails the way
        // Chrome fails it rather than silently matching nothing.
        const runtimeContextFilter = (value) => {
            if (value === undefined || value === null
                || typeof value === "function") {
                return {};
            }
            if (typeof value !== "object" || Array.isArray(value)) {
                throw new TypeError(
                    "runtime.getContexts: filter must be an object."
                );
            }
            const filter = {};
            for (const name of runtimeContextFilterArrays) {
                const entry = value[name];
                if (entry === undefined || entry === null) continue;
                if (!Array.isArray(entry)) {
                    throw new TypeError(
                        `runtime.getContexts: ${name} must be an array.`
                    );
                }
                filter[name] = Array.from(entry);
            }
            if (value.incognito !== undefined && value.incognito !== null) {
                if (typeof value.incognito !== "boolean") {
                    throw new TypeError(
                        "runtime.getContexts: incognito must be a boolean."
                    );
                }
                filter.incognito = value.incognito;
            }
            return filter;
        };
        const runtimeContextMatches = (context, filter) => {
            const matches = (name, value) => !Array.isArray(filter[name])
                || filter[name].some((entry) => entry === value);
            return matches("contextIds", context.contextId)
                && matches("contextTypes", context.contextType)
                && matches("documentIds", context.documentId)
                && matches("documentOrigins", context.documentOrigin)
                && matches("documentUrls", context.documentUrl)
                && matches("frameIds", context.frameId)
                && matches("tabIds", context.tabId)
                && matches("windowIds", context.windowId)
                && (filter.incognito === undefined
                    || filter.incognito === context.incognito);
        };
        // Chrome sets `documentUrl` on a BACKGROUND context only when the
        // background is a document. Read that from the package's own declared
        // manifest rather than from however Crest happens to host it, so an
        // MV3 worker package sees the absent `documentUrl` Chrome gives it.
        const runtimeBackgroundDocumentURL = () => {
            const background = declaredManifest?.background;
            if (!background || typeof background !== "object") return undefined;
            if (typeof background.page === "string" && background.page) {
                return fallbackResourceURL(background.page);
            }
            if (typeof background.service_worker === "string"
                && background.service_worker) {
                return undefined;
            }
            if (Array.isArray(background.scripts)
                && background.scripts.length > 0) {
                return fallbackResourceURL("_generated_background_page.html");
            }
            return undefined;
        };
        // Swift reports a context's tab and window as a Space-relative tab
        // index plus that tab's URL, exactly as the sidebar event channel
        // does: WebKit owns the numeric IDs, and inventing one here would
        // disagree with `tabs.query`. Resolve them through the same helpers.
        const runtimeExtensionContexts = async (filter) => {
            const response = await requestCapability(
                "runtime.getContexts",
                { filter },
                []
            );
            const reported = Array.isArray(response?.contexts)
                ? response.contexts
                : [];
            let resolvedWindowId;
            const primaryWindowId = async () => {
                if (resolvedWindowId !== undefined) return resolvedWindowId;
                try {
                    resolvedWindowId = await sidebarPrimaryWindowId();
                } catch {
                    resolvedWindowId = -1;
                }
                return resolvedWindowId;
            };
            const contexts = [];
            for (const entry of reported) {
                if (!entry || typeof entry !== "object") continue;
                const contextType = entry.contextType;
                if (!Object.hasOwn(runtimeContextTypes, contextType)) continue;
                let windowId = -1;
                let tabId = -1;
                if (entry.windowKind === "primary") {
                    windowId = await primaryWindowId();
                }
                if (windowId >= 0 && Number.isInteger(entry.tabIndex)) {
                    try {
                        tabId = await sidebarTabIdFor(
                            windowId,
                            entry.tabIndex,
                            typeof entry.tabURL === "string"
                                ? entry.tabURL
                                : undefined
                        );
                    } catch {
                        tabId = -1;
                    }
                }
                const context = {
                    contextId: String(entry.contextId ?? ""),
                    contextType,
                    frameId: Number.isInteger(entry.frameId)
                        ? entry.frameId
                        : 0,
                    incognito: entry.incognito === true,
                    tabId,
                    windowId
                };
                const documentUrl = contextType === "BACKGROUND"
                    ? runtimeBackgroundDocumentURL()
                    : (typeof entry.documentUrl === "string"
                        ? entry.documentUrl
                        : undefined);
                if (documentUrl !== undefined) {
                    context.documentUrl = documentUrl;
                }
                if (typeof entry.documentOrigin === "string") {
                    context.documentOrigin = entry.documentOrigin;
                }
                if (typeof entry.documentId === "string") {
                    context.documentId = entry.documentId;
                }
                contexts.push(context);
            }
            // Swift filters on `contextTypes` so it can skip work it would
            // otherwise do; the complete predicate runs here, where the
            // numeric tab and window IDs the filter names actually exist.
            return contexts.filter(
                (context) => runtimeContextMatches(context, filter)
            );
        };
        const runtimeGetContexts = (...args) => {
            let filter;
            try {
                filter = runtimeContextFilter(args[0]);
            } catch (error) {
                return rejectCallbackOrPromise(
                    args,
                    error?.message ?? "runtime.getContexts: invalid filter."
                );
            }
            const response = runtimeExtensionContexts(filter);
            const callback = args.at(-1);
            if (typeof callback !== "function") return response;
            response.then(
                (value) => callback(value),
                (error) => invokeCallbackWithLastError(
                    callback,
                    error?.message ?? "runtime.getContexts failed."
                )
            );
            return undefined;
        };
        // Chrome's ColorArray is [r, g, b, a], each an integer in 0...255; the
        // string form is any CSS color. Crest draws its own toolbar badge and
        // has no per-extension text color to change, so a valid call is
        // accepted and resolved and nothing is rendered differently. Rejecting
        // it would be worse: packages call this inside a try that treats a
        // throw as "badges are broken".
        const actionBadgeColor = (value) => {
            if (typeof value === "string") {
                if (value.length === 0) {
                    throw new TypeError("The color must not be empty.");
                }
                return;
            }
            if (!Array.isArray(value) || value.length !== 4
                || !value.every((component) => Number.isInteger(component)
                    && component >= 0 && component <= 255)) {
                throw new TypeError(
                    "The color must be a CSS color string or an array of four integers in 0...255."
                );
            }
        };
        const actionSetBadgeTextColor = (...args) => {
            const details = args[0];
            try {
                if (!details || typeof details !== "object"
                    || Array.isArray(details)) {
                    throw new TypeError(
                        "setBadgeTextColor requires a details object."
                    );
                }
                if (details.color === undefined || details.color === null) {
                    throw new TypeError(
                        "setBadgeTextColor requires a color."
                    );
                }
                actionBadgeColor(details.color);
                if (details.tabId !== undefined && details.tabId !== null
                    && (!Number.isInteger(details.tabId)
                        || details.tabId < 0)) {
                    throw new TypeError(`Invalid tab ID: ${details.tabId}`);
                }
            } catch (error) {
                return rejectCallbackOrPromise(
                    args,
                    error?.message ?? "setBadgeTextColor failed."
                );
            }
            return callbackOrPromise(args, undefined);
        };
        // Merged in place so `action` and `browserAction` keep the single
        // shared identity `fallbacksFor` depends on, and so neither object
        // literal above has to name a member declared after it.
        Object.assign(runtime, runtimeSchemaEnums, {
            getContexts: runtimeGetContexts
        });
        Object.assign(action, {
            setBadgeTextColor: actionSetBadgeTextColor,
            // Crest has no toolbar-pinning change to report to an extension,
            // so this registry is real and permanently silent. ChatGPT's
            // worker does `chrome.action.onUserSettingsChanged?.addListener`,
            // which needs the object to exist and accept a listener.
            onUserSettingsChanged: presenceOnlyEvent(
                "action.onUserSettingsChanged"
            )
        });
        """#
}
