/// Included inside the compatibility runtime's lexical scope. The matrix owns
/// publication; defining this object never makes an unavailable API visible.
///
/// WebKit implements `declarativeNetRequest`'s methods but publishes none of
/// the schema's enums or numeric limits. Portable rule builders dereference
/// them unguarded — Claude's session-rule builder reads
/// `RuleActionType.MODIFY_HEADERS`, `HeaderOperation.SET` and
/// `ResourceType.WEBSOCKET` while composing a rule — so an absent enum throws
/// where the package expected a string constant.
///
/// The object is deliberately empty when WebKit publishes no
/// `declarativeNetRequest` namespace at all. A namespace carrying constants
/// and no `updateDynamicRules` is worse than an absent one: feature detection
/// succeeds and the next call throws.
///
/// The fragment also owns the header-rule emulation. WebKit validates every
/// `modifyHeaders` header name against a fixed list and rejects the *whole
/// rule* when one name is missing, so a package that sets a custom header
/// loses the standard headers in the same rule. The wrappers below partition
/// each rule — the acceptable operations go to WebKit, the rest are held by
/// Crest — and apply what Crest holds to the requests the extension itself
/// makes. See `Documentation/ExtensionEmulationServices.md`.
enum BrowserExtensionDeclarativeNetRequestCompatibilityScript {
    /// One Swift constant per table, serialized for the runtime, so the
    /// partition the runtime performs and the partition Crest documents can
    /// never be two different lists.
    static var headerPolicyTables: String {
        let policy = BrowserExtensionDeclarativeNetRequestHeaderPolicy.self
        return """
            const declarativeNetRequestWebKitAcceptedHeaderNames = \
            \(javascriptStringSet(policy.webKitAcceptedHeaderNames));
            const declarativeNetRequestFetchForbiddenHeaderNames = \
            \(javascriptStringSet(policy.fetchForbiddenHeaderNames));
            const declarativeNetRequestFetchForbiddenHeaderPrefixes = \
            \(javascriptStringArray(policy.fetchForbiddenHeaderNamePrefixes));
            """
    }

    static var source: String { headerPolicyTables + "\n" + body }

    private static func javascriptStringSet(_ values: [String]) -> String {
        "new Set(\(javascriptStringArray(values)))"
    }

    /// The names are ASCII header tokens from a Swift constant, never user
    /// input, so a literal quote is the whole encoding.
    private static func javascriptStringArray(_ values: [String]) -> String {
        "[" + values.map { "\"\($0)\"" }.joined(separator: ", ") + "]"
    }

    private static let body = #"""
        const nativeDeclarativeNetRequest = (() => {
            for (const root of [nativeChrome, nativeBrowser, primaryRoot]) {
                let value;
                try { value = root?.declarativeNetRequest; } catch {}
                if (value) return value;
            }
            return undefined;
        })();
        // Member for member from the pinned Chromium
        // `extensions/common/api/declarative_net_request.webidl`. Enum keys are
        // Chrome's generated UPPER_SNAKE spelling of each schema value.
        const declarativeNetRequest = nativeDeclarativeNetRequest === undefined
            ? {}
            : {
                ResourceType: Object.freeze({
                    MAIN_FRAME: "main_frame",
                    SUB_FRAME: "sub_frame",
                    STYLESHEET: "stylesheet",
                    SCRIPT: "script",
                    IMAGE: "image",
                    FONT: "font",
                    OBJECT: "object",
                    XMLHTTPREQUEST: "xmlhttprequest",
                    PING: "ping",
                    CSP_REPORT: "csp_report",
                    MEDIA: "media",
                    WEBSOCKET: "websocket",
                    WEBTRANSPORT: "webtransport",
                    WEBBUNDLE: "webbundle",
                    OTHER: "other"
                }),
                RequestMethod: Object.freeze({
                    CONNECT: "connect",
                    DELETE: "delete",
                    GET: "get",
                    HEAD: "head",
                    OPTIONS: "options",
                    PATCH: "patch",
                    POST: "post",
                    PUT: "put",
                    OTHER: "other"
                }),
                DomainType: Object.freeze({
                    FIRST_PARTY: "firstParty",
                    THIRD_PARTY: "thirdParty"
                }),
                HeaderOperation: Object.freeze({
                    APPEND: "append",
                    SET: "set",
                    REMOVE: "remove"
                }),
                RuleActionType: Object.freeze({
                    BLOCK: "block",
                    REDIRECT: "redirect",
                    ALLOW: "allow",
                    UPGRADE_SCHEME: "upgradeScheme",
                    MODIFY_HEADERS: "modifyHeaders",
                    ALLOW_ALL_REQUESTS: "allowAllRequests"
                }),
                UnsupportedRegexReason: Object.freeze({
                    SYNTAX_ERROR: "syntaxError",
                    MEMORY_LIMIT_EXCEEDED: "memoryLimitExceeded"
                }),
                DYNAMIC_RULESET_ID: "_dynamic",
                SESSION_RULESET_ID: "_session",
                GUARANTEED_MINIMUM_STATIC_RULES: 30000,
                GETMATCHEDRULES_QUOTA_INTERVAL: 10,
                MAX_GETMATCHEDRULES_CALLS_PER_INTERVAL: 20,
                MAX_NUMBER_OF_DYNAMIC_AND_SESSION_RULES: 5000,
                MAX_NUMBER_OF_DYNAMIC_RULES: 30000,
                MAX_NUMBER_OF_ENABLED_STATIC_RULESETS: 50,
                MAX_NUMBER_OF_REGEX_RULES: 1000,
                MAX_NUMBER_OF_SESSION_RULES: 5000,
                MAX_NUMBER_OF_STATIC_RULESETS: 100,
                MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES: 5000,
                MAX_NUMBER_OF_UNSAFE_SESSION_RULES: 5000
            };

        // ---------------------------------------------------------------
        // Emulated `modifyHeaders` request headers
        // ---------------------------------------------------------------
        //
        // WebKit's `isHeaderNameValid` accepts a fixed list of standard header
        // names and rejects the entire rule otherwise: "Rule with id 1 is
        // invalid. The header `anthropic-client-platform` is not recognized."
        // Chrome applies such a rule to every request the extension makes, and
        // packages depend on it — Claude's Messages API refuses a request that
        // arrives without its first-party client headers. So Crest keeps the
        // half WebKit accepts native and applies the other half itself, to the
        // extension's own `fetch` and `XMLHttpRequest` traffic. Content-script
        // and page requests are outside this boundary; so is `User-Agent`,
        // which no script may set.
        const declarativeNetRequestRulesetNames = Object.freeze(["session", "dynamic"]);
        let declarativeNetRequestEmulatedRules = {session: [], dynamic: []};
        const declarativeNetRequestEmulates =
            nativeDeclarativeNetRequest !== undefined
            && isPrivilegedExtensionContext
            && namespaceUsesCompatibility("declarativeNetRequest");

        const declarativeNetRequestHeaderIsNative = (name) =>
            typeof name === "string"
            && declarativeNetRequestWebKitAcceptedHeaderNames.has(name.toLowerCase());
        const declarativeNetRequestHeaderIsForbidden = (name) => {
            const lowered = String(name ?? "").toLowerCase();
            if (declarativeNetRequestFetchForbiddenHeaderNames.has(lowered)) return true;
            return declarativeNetRequestFetchForbiddenHeaderPrefixes.some(
                (prefix) => lowered.startsWith(prefix)
            );
        };

        const declarativeNetRequestCondition = (value) => {
            const condition = {};
            if (!value || typeof value !== "object") return condition;
            for (const key of ["urlFilter", "regexFilter"]) {
                if (typeof value[key] === "string") condition[key] = value[key];
            }
            condition.isUrlFilterCaseSensitive = value.isUrlFilterCaseSensitive === true;
            for (const key of [
                "resourceTypes",
                "excludedResourceTypes",
                "requestMethods",
                "excludedRequestMethods"
            ]) {
                if (!Array.isArray(value[key])) continue;
                const entries = value[key].filter((entry) => typeof entry === "string");
                if (entries.length > 0) condition[key] = entries;
            }
            return condition;
        };
        const declarativeNetRequestRule = (value) => {
            if (!value || typeof value !== "object" || !Number.isInteger(value.id)) {
                return undefined;
            }
            const headers = (Array.isArray(value.requestHeaders) ? value.requestHeaders : [])
                .filter((entry) =>
                    entry
                    && typeof entry.header === "string"
                    && entry.header.length > 0
                    && (entry.operation === "set"
                        || entry.operation === "append"
                        || entry.operation === "remove")
                )
                .map((entry) => entry.operation === "remove"
                    ? {header: entry.header, operation: "remove"}
                    : {
                        header: entry.header,
                        operation: entry.operation,
                        value: String(entry.value ?? "")
                    });
            if (headers.length === 0) return undefined;
            return {
                id: value.id,
                priority: Number.isInteger(value.priority) ? value.priority : 1,
                condition: declarativeNetRequestCondition(value.condition),
                requestHeaders: headers
            };
        };

        // One rule in, at most one native rule and one emulated rule out.
        const declarativeNetRequestPartition = (rule) => {
            const action = rule && typeof rule === "object" ? rule.action : undefined;
            if (
                !action
                || action.type !== "modifyHeaders"
                || !Array.isArray(action.requestHeaders)
            ) {
                return {nativeRule: rule, emulatedRule: undefined};
            }
            const accepted = [];
            const rejected = [];
            for (const entry of action.requestHeaders) {
                if (declarativeNetRequestHeaderIsNative(entry?.header)) accepted.push(entry);
                else rejected.push(entry);
            }
            if (rejected.length === 0) return {nativeRule: rule, emulatedRule: undefined};
            const emulatedRule = declarativeNetRequestRule({
                id: rule.id,
                priority: rule.priority,
                condition: rule.condition,
                requestHeaders: rejected
            });
            const nativeAction = {...action};
            if (accepted.length > 0) nativeAction.requestHeaders = accepted;
            else delete nativeAction.requestHeaders;
            const modifiesResponse = Array.isArray(nativeAction.responseHeaders)
                && nativeAction.responseHeaders.length > 0;
            // WebKit requires a `modifyHeaders` rule to carry at least one
            // header operation. A rule whose every request-header operation
            // Crest took over, and which changes no response header, has
            // nothing left to send.
            if (accepted.length === 0 && !modifiesResponse) {
                return {nativeRule: undefined, emulatedRule};
            }
            return {nativeRule: {...rule, action: nativeAction}, emulatedRule};
        };

        const declarativeNetRequestApplyRulesets = (payload) => {
            if (!payload || typeof payload !== "object") return false;
            const next = {session: [], dynamic: []};
            for (const name of declarativeNetRequestRulesetNames) {
                next[name] = (Array.isArray(payload[name]) ? payload[name] : [])
                    .map(declarativeNetRequestRule)
                    .filter((rule) => rule !== undefined);
            }
            declarativeNetRequestEmulatedRules = next;
            return true;
        };
        let declarativeNetRequestWarnedBroker = false;
        const declarativeNetRequestPublish = async (ruleset) => {
            try {
                await requestCapability(
                    "dnr.setEmulatedHeaderRules",
                    {ruleset, rules: declarativeNetRequestEmulatedRules[ruleset]},
                    []
                );
            } catch (error) {
                // WebKit accepted what it could, so the call itself succeeded.
                // Rejecting here would abort a worker bootstrap over headers
                // that are, at worst, missing.
                if (declarativeNetRequestWarnedBroker) return;
                declarativeNetRequestWarnedBroker = true;
                try {
                    console.warn(
                        `Crest could not record this extension's declarativeNetRequest header rules, so its custom request headers will not be applied: ${error?.message ?? error}`
                    );
                } catch {}
            }
        };

        // MARK: rule matching
        //
        // `BrowserExtensionEmulatedHeaderRuleMatcher` is the reference
        // implementation of this grammar and the two are pinned by the same
        // cases; the decision has to be made here because this is the context
        // that issues the request.
        const declarativeNetRequestAcceptedResourceTypes = new Set([
            "xmlhttprequest", "other"
        ]);
        const declarativeNetRequestExpressions = new Map();
        const declarativeNetRequestExpression = (pattern, isCaseSensitive) => {
            const key = `${isCaseSensitive ? "s" : "i"} ${pattern}`;
            if (declarativeNetRequestExpressions.has(key)) {
                return declarativeNetRequestExpressions.get(key);
            }
            let expression;
            try {
                expression = new RegExp(pattern, isCaseSensitive ? "" : "i");
            } catch {
                // Chrome discards a rule whose pattern will not compile.
                // Matching nothing is the same outcome without a throw
                // reaching the request.
                expression = undefined;
            }
            declarativeNetRequestExpressions.set(key, expression);
            return expression;
        };
        const declarativeNetRequestEscape = (character) =>
            character.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&");
        // `||` anchors to the start of a host or any of its dot-separated
        // parents, `|` to the start or end of the URL, `*` spans anything, and
        // `^` is a separator: anything that is not a letter, digit, `_`, `-`,
        // `.` or `%`, or the end of the URL.
        const declarativeNetRequestURLFilterPattern = (urlFilter) => {
            const characters = Array.from(urlFilter);
            let pattern = "";
            let index = 0;
            if (characters[0] === "|") {
                if (characters[1] === "|") {
                    pattern += "^[^:/?#]+://(?:[^/?#]*\\.)?";
                    index = 2;
                } else {
                    pattern += "^";
                    index = 1;
                }
            }
            let end = characters.length;
            let anchorsEnd = false;
            if (end > index && characters[end - 1] === "|") {
                anchorsEnd = true;
                end -= 1;
            }
            while (index < end) {
                const character = characters[index];
                if (character === "*") pattern += ".*";
                else if (character === "^") pattern += "(?:[^A-Za-z0-9_\\-.%]|$)";
                else pattern += declarativeNetRequestEscape(character);
                index += 1;
            }
            if (anchorsEnd) pattern += "$";
            return pattern;
        };
        const declarativeNetRequestMatches = (rule, url, method) => {
            const condition = rule.condition ?? {};
            if (
                Array.isArray(condition.resourceTypes)
                && !condition.resourceTypes.some(
                    (type) => declarativeNetRequestAcceptedResourceTypes.has(type)
                )
            ) {
                return false;
            }
            if (
                Array.isArray(condition.excludedResourceTypes)
                && condition.excludedResourceTypes.includes("xmlhttprequest")
            ) {
                return false;
            }
            const normalizedMethod = String(method ?? "get").toLowerCase();
            if (
                Array.isArray(condition.requestMethods)
                && !condition.requestMethods.includes(normalizedMethod)
            ) {
                return false;
            }
            if (
                Array.isArray(condition.excludedRequestMethods)
                && condition.excludedRequestMethods.includes(normalizedMethod)
            ) {
                return false;
            }
            const caseSensitive = condition.isUrlFilterCaseSensitive === true;
            if (typeof condition.regexFilter === "string" && condition.regexFilter) {
                const expression = declarativeNetRequestExpression(
                    condition.regexFilter, caseSensitive
                );
                if (!expression || !expression.test(url)) return false;
            }
            if (typeof condition.urlFilter === "string" && condition.urlFilter) {
                const expression = declarativeNetRequestExpression(
                    declarativeNetRequestURLFilterPattern(condition.urlFilter), caseSensitive
                );
                if (!expression || !expression.test(url)) return false;
            }
            return true;
        };
        // One operation wins per header name: the highest priority, and among
        // equal priorities the lowest rule id.
        const declarativeNetRequestModifications = (url, method) => {
            const rules = [
                ...declarativeNetRequestEmulatedRules.session,
                ...declarativeNetRequestEmulatedRules.dynamic
            ];
            if (rules.length === 0) return [];
            const winners = new Map();
            for (const rule of rules) {
                if (!declarativeNetRequestMatches(rule, url, method)) continue;
                for (const entry of rule.requestHeaders) {
                    const name = entry.header.toLowerCase();
                    const existing = winners.get(name);
                    if (existing) {
                        const outranks = rule.priority > existing.rule.priority
                            || (rule.priority === existing.rule.priority
                                && rule.id < existing.rule.id);
                        if (!outranks) continue;
                    }
                    winners.set(name, {rule, entry});
                }
            }
            return Array.from(winners.keys()).sort().map((name) => winners.get(name).entry);
        };

        // MARK: tracing
        //
        // Header *names* only, never values: a `set` operation on an
        // `authorization` header is exactly the sort of thing that must not be
        // written to a diagnostics channel.
        const declarativeNetRequestSkippedHeaders = new Set();
        const declarativeNetRequestTraceSkipped = (name) => {
            if (!capturesExtensionConsole) return;
            const lowered = String(name ?? "").toLowerCase();
            if (declarativeNetRequestSkippedHeaders.has(lowered)) return;
            declarativeNetRequestSkippedHeaders.add(lowered);
            try {
                reportRuntimeTrace("dnr.emulatedHeaders.skipped", {
                    context: executionProcess,
                    header: lowered
                });
            } catch {}
        };
        const declarativeNetRequestTracedApplications = new Set();
        const declarativeNetRequestTraceApplied = (url, names) => {
            if (!capturesExtensionConsole || names.length === 0) return;
            let host = "";
            try { host = new URL(url).host; } catch {}
            const headers = names.map((name) => name.toLowerCase()).sort();
            const key = `${host} ${headers.join(",")}`;
            if (declarativeNetRequestTracedApplications.has(key)) return;
            declarativeNetRequestTracedApplications.add(key);
            try {
                reportRuntimeTrace("dnr.emulatedHeaders.applied", {
                    context: executionProcess,
                    host,
                    headers
                });
            } catch {}
        };

        // MARK: request instrumentation
        const declarativeNetRequestResourceURL = (resource) => {
            let raw;
            if (typeof resource === "string") raw = resource;
            else if (resource && typeof resource.url === "string") raw = resource.url;
            else raw = String(resource ?? "");
            try { return new URL(raw, globalThis.location?.href).href; } catch { return raw; }
        };
        const declarativeNetRequestResourceMethod = (resource, options) => {
            if (typeof options?.method === "string") return options.method;
            if (resource && typeof resource === "object" && typeof resource.method === "string") {
                return resource.method;
            }
            return "get";
        };
        const declarativeNetRequestHeaders = (resource, options) => {
            if (options && options.headers !== undefined) return new Headers(options.headers);
            if (resource && typeof resource === "object" && resource.headers) {
                return new Headers(resource.headers);
            }
            return new Headers();
        };
        const declarativeNetRequestApply = (headers, modifications) => {
            const applied = [];
            for (const entry of modifications) {
                if (declarativeNetRequestHeaderIsForbidden(entry.header)) {
                    declarativeNetRequestTraceSkipped(entry.header);
                    continue;
                }
                try {
                    if (entry.operation === "remove") headers.delete(entry.header);
                    else if (entry.operation === "append") {
                        headers.append(entry.header, entry.value ?? "");
                    } else headers.set(entry.header, entry.value ?? "");
                    applied.push(entry.header);
                } catch {
                    declarativeNetRequestTraceSkipped(entry.header);
                }
            }
            return applied;
        };
        const declarativeNetRequestInstallFetch = () => {
            const nativeFetch = globalThis.fetch;
            if (typeof nativeFetch !== "function") return;
            const wrapped = function fetch(resource, options) {
                let url = "";
                let modifications = [];
                try {
                    url = declarativeNetRequestResourceURL(resource);
                    modifications = url
                        ? declarativeNetRequestModifications(
                            url, declarativeNetRequestResourceMethod(resource, options))
                        : [];
                } catch { modifications = []; }
                if (modifications.length === 0) {
                    return Reflect.apply(nativeFetch, this, arguments);
                }
                try {
                    const headers = declarativeNetRequestHeaders(resource, options);
                    const applied = declarativeNetRequestApply(headers, modifications);
                    if (applied.length === 0) return Reflect.apply(nativeFetch, this, arguments);
                    declarativeNetRequestTraceApplied(url, applied);
                    // Supplying `headers` in the init replaces the request's
                    // header list without cloning its body, which a
                    // `new Request(input, …)` round trip would disturb.
                    return Reflect.apply(
                        nativeFetch, this, [resource, {...(options ?? {}), headers}]
                    );
                } catch {
                    return Reflect.apply(nativeFetch, this, arguments);
                }
            };
            try {
                Object.defineProperty(globalThis, "fetch", {
                    value: wrapped, writable: true, configurable: true
                });
            } catch {
                try { globalThis.fetch = wrapped; } catch {}
            }
        };
        const declarativeNetRequestInstallXMLHttpRequest = () => {
            const prototype = globalThis.XMLHttpRequest?.prototype;
            const nativeOpen = prototype?.open;
            const nativeSend = prototype?.send;
            const nativeSetRequestHeader = prototype?.setRequestHeader;
            if (
                typeof nativeOpen !== "function"
                || typeof nativeSend !== "function"
                || typeof nativeSetRequestHeader !== "function"
            ) {
                return;
            }
            const pending = new WeakMap();
            prototype.open = function open(method, url) {
                try {
                    pending.set(this, {
                        method: typeof method === "string" ? method : "get",
                        url: declarativeNetRequestResourceURL(url),
                        headers: new Set()
                    });
                } catch {}
                return Reflect.apply(nativeOpen, this, arguments);
            };
            prototype.setRequestHeader = function setRequestHeader(name) {
                try { pending.get(this)?.headers.add(String(name).toLowerCase()); } catch {}
                return Reflect.apply(nativeSetRequestHeader, this, arguments);
            };
            prototype.send = function send() {
                try {
                    const record = pending.get(this);
                    if (record) {
                        const applied = [];
                        for (const entry of declarativeNetRequestModifications(
                            record.url, record.method
                        )) {
                            const name = entry.header.toLowerCase();
                            if (declarativeNetRequestHeaderIsForbidden(name)) {
                                declarativeNetRequestTraceSkipped(name);
                                continue;
                            }
                            // `setRequestHeader` can only add to a header list.
                            // It cannot replace or delete what the caller
                            // already set, so those operations are reported
                            // rather than half-applied.
                            if (record.headers.has(name)) {
                                if (entry.operation !== "append") {
                                    declarativeNetRequestTraceSkipped(name);
                                    continue;
                                }
                            } else if (entry.operation === "remove") {
                                continue;
                            }
                            try {
                                Reflect.apply(
                                    nativeSetRequestHeader, this,
                                    [entry.header, entry.value ?? ""]
                                );
                                applied.push(entry.header);
                            } catch {
                                declarativeNetRequestTraceSkipped(name);
                            }
                        }
                        declarativeNetRequestTraceApplied(record.url, applied);
                    }
                } catch {}
                return Reflect.apply(nativeSend, this, arguments);
            };
        };

        // MARK: namespace wrappers
        const declarativeNetRequestSettle = (args, promise) => {
            const callback = args.at(-1);
            if (typeof callback === "function") {
                promise.then(
                    (value) => callback(value),
                    (error) => invokeCallbackWithLastError(
                        callback,
                        error?.message ?? "declarativeNetRequest failed."
                    )
                );
                return undefined;
            }
            return promise;
        };
        const declarativeNetRequestUpdate = (ruleset, nativeMethod, owner, args) => {
            const options = args[0];
            const removeRuleIds = Array.isArray(options?.removeRuleIds)
                ? options.removeRuleIds.filter(Number.isInteger)
                : [];
            const addRules = Array.isArray(options?.addRules) ? options.addRules : [];
            const emulatedAdditions = [];
            let nativeOptions = options;
            if (addRules.length > 0) {
                const nativeAddRules = [];
                let partitioned = false;
                for (const rule of addRules) {
                    const {nativeRule, emulatedRule} = declarativeNetRequestPartition(rule);
                    if (nativeRule !== undefined) nativeAddRules.push(nativeRule);
                    if (emulatedRule !== undefined) {
                        emulatedAdditions.push(emulatedRule);
                        partitioned = true;
                    }
                }
                if (partitioned) nativeOptions = {...options, addRules: nativeAddRules};
            }
            return declarativeNetRequestSettle(args, (async () => {
                // WebKit answers first. If it refuses for a reason Crest did
                // not cause, that error reaches the extension unchanged and
                // Crest records nothing the browser did not accept.
                const result = await Reflect.apply(nativeMethod, owner, [nativeOptions]);
                const previous = declarativeNetRequestEmulatedRules[ruleset];
                const removed = new Set(removeRuleIds);
                for (const rule of emulatedAdditions) removed.add(rule.id);
                const next = previous
                    .filter((rule) => !removed.has(rule.id))
                    .concat(emulatedAdditions);
                if (emulatedAdditions.length === 0 && next.length === previous.length) {
                    return result;
                }
                declarativeNetRequestEmulatedRules = {
                    ...declarativeNetRequestEmulatedRules,
                    [ruleset]: next
                };
                await declarativeNetRequestPublish(ruleset);
                return result;
            })());
        };
        // The extension must read back what it set, whichever half of the rule
        // ended up where.
        const declarativeNetRequestMerge = (ruleset, nativeRules, filter) => {
            const emulated = declarativeNetRequestEmulatedRules[ruleset];
            const rules = Array.isArray(nativeRules) ? nativeRules : [];
            if (emulated.length === 0) return rules;
            const ids = Array.isArray(filter?.ruleIds)
                ? new Set(filter.ruleIds.filter(Number.isInteger))
                : undefined;
            const pending = new Map();
            for (const rule of emulated) {
                if (ids && !ids.has(rule.id)) continue;
                pending.set(rule.id, rule);
            }
            if (pending.size === 0) return rules;
            const merged = [];
            for (const rule of rules) {
                const extra = Number.isInteger(rule?.id) ? pending.get(rule.id) : undefined;
                if (!extra) {
                    merged.push(rule);
                    continue;
                }
                pending.delete(rule.id);
                const action = {...(rule.action ?? {})};
                action.requestHeaders = [
                    ...(Array.isArray(action.requestHeaders) ? action.requestHeaders : []),
                    ...extra.requestHeaders.map((entry) => ({...entry}))
                ];
                merged.push({...rule, action});
            }
            // A rule whose every request-header operation Crest owns was never
            // sent to WebKit, so nothing native carries its id.
            for (const rule of pending.values()) {
                merged.push({
                    id: rule.id,
                    priority: rule.priority,
                    condition: {...rule.condition},
                    action: {
                        type: "modifyHeaders",
                        requestHeaders: rule.requestHeaders.map((entry) => ({...entry}))
                    }
                });
            }
            return merged;
        };
        const declarativeNetRequestRead = (ruleset, nativeMethod, owner, args) => {
            const filter = args[0] && typeof args[0] === "object" ? args[0] : undefined;
            return declarativeNetRequestSettle(args, (async () => {
                const native = await Reflect.apply(
                    nativeMethod, owner, filter === undefined ? [] : [filter]
                );
                return declarativeNetRequestMerge(ruleset, native, filter);
            })());
        };

        const declarativeNetRequestPatchedNamespaces = new WeakSet();
        // Patched in place rather than behind a `namespaceFacade`: the
        // constants above are installed onto this same object afterwards by
        // `installFallbacks`, and a facade would have to carry every one of
        // them as its fallback to keep them reachable. `runtime.getManifest`
        // is overridden the same way and for the same reason — WebKit's own
        // object stays the object extensions hold.
        const normalizeDeclarativeNetRequestNamespace = (nativeNamespace) => {
            if (!declarativeNetRequestEmulates || !nativeNamespace) return nativeNamespace;
            if (declarativeNetRequestPatchedNamespaces.has(nativeNamespace)) {
                return nativeNamespace;
            }
            declarativeNetRequestPatchedNamespaces.add(nativeNamespace);
            const wrappers = [
                ["updateSessionRules", "session", declarativeNetRequestUpdate],
                ["updateDynamicRules", "dynamic", declarativeNetRequestUpdate],
                ["getSessionRules", "session", declarativeNetRequestRead],
                ["getDynamicRules", "dynamic", declarativeNetRequestRead]
            ];
            for (const [name, ruleset, wrap] of wrappers) {
                if (!memberUsesCompatibility(`declarativeNetRequest.${name}`)) continue;
                let nativeMethod;
                try { nativeMethod = nativeNamespace[name]; } catch {}
                if (typeof nativeMethod !== "function") continue;
                const wrapped = {
                    [name](...args) {
                        return wrap(ruleset, nativeMethod, nativeNamespace, args);
                    }
                }[name];
                try {
                    Object.defineProperty(nativeNamespace, name, {
                        value: wrapped,
                        writable: true,
                        configurable: true,
                        enumerable: true
                    });
                } catch {
                    try { nativeNamespace[name] = wrapped; } catch {}
                }
            }
            return nativeNamespace;
        };

        const declarativeNetRequestHeaderRuleWatch = capabilityWatch({
            api: "dnr",
            hasListeners: () => declarativeNetRequestEmulates,
            subscription: () => ({api: "dnr.watch"}),
            onMessage: (message) => {
                if (message?.api !== "dnr.event") return;
                declarativeNetRequestApplyRulesets(message.rulesets);
            }
        });
        if (declarativeNetRequestEmulates) {
            declarativeNetRequestInstallFetch();
            declarativeNetRequestInstallXMLHttpRequest();
            declarativeNetRequestHeaderRuleWatch.connect();
            // A request made before the first table arrives is not modified.
            // The worker sets its rules at startup, long before a panel or a
            // popup exists to make one.
            Promise.resolve().then(async () => {
                try {
                    const response = await requestCapability("dnr.emulatedHeaderRules", {}, []);
                    declarativeNetRequestApplyRulesets(response?.rulesets);
                } catch {}
            });
        }
        """#
}
