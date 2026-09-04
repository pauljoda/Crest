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
enum BrowserExtensionDeclarativeNetRequestCompatibilityScript {
    static let source = #"""
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
        """#
}
