import Foundation

/// Which `declarativeNetRequest` ruleset an emulated rule belongs to.
///
/// Chrome's two writable rulesets have different lifetimes: session rules die
/// with the extension's context, dynamic rules survive a relaunch. Crest keeps
/// the same split so an extension that sets one and reads back the other is
/// not told a story WebKit would contradict.
enum BrowserExtensionEmulatedHeaderRuleset: String, CaseIterable, Sendable {
    case session
    case dynamic
}

/// Failures the `declarativeNetRequest` header broker reports to an extension.
enum BrowserExtensionEmulatedHeaderRuleError: LocalizedError, Equatable {
    case invalidRequest
    case unsupportedCondition(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "The extension supplied an invalid declarativeNetRequest header rule request."
        case .unsupportedCondition(let name):
            "Crest cannot emulate the declarativeNetRequest condition \(name)."
        case .unavailable:
            "Crest's declarativeNetRequest header emulation is unavailable."
        }
    }
}

/// One `modifyHeaders` rule's *request*-header operations that WebKit refused.
///
/// WebKit validates every `modifyHeaders` header name against a fixed list of
/// standard names and rejects the whole rule when one name is not on it — see
/// `BrowserExtensionDeclarativeNetRequestHeaderPolicy.webKitAcceptedHeaderNames`.
/// A custom header such as `anthropic-client-platform` can therefore never
/// pass, and Chrome's behaviour (the header is added to every matching request
/// the extension makes) is what the package was written against. Crest keeps
/// the acceptable half of the rule native and records the rest here, so the
/// compatibility runtime can apply it to the extension's own `fetch` and
/// `XMLHttpRequest` traffic.
///
/// This is the wire shape as well as the stored shape: the field names are
/// Chrome's, so a rule can be handed back through `getSessionRules` merged
/// into the native result without a second vocabulary.
struct BrowserExtensionEmulatedHeaderRule: Equatable, Sendable {
    enum HeaderOperation: String, CaseIterable, Sendable {
        case set
        case append
        case remove
    }

    /// One `action.requestHeaders` entry.
    struct HeaderModification: Equatable, Sendable {
        /// The name exactly as the extension authored it. Matching is
        /// case-insensitive; the authored spelling is what goes on the wire.
        let header: String
        let operation: HeaderOperation
        /// Absent for `remove`, required for `set` and `append`.
        let value: String?

        init(header: String, operation: HeaderOperation, value: String? = nil) {
            self.header = header
            self.operation = operation
            self.value = value
        }
    }

    /// The subset of Chrome's `RuleCondition` this emulation can honour.
    ///
    /// Conditions requiring engine-owned initiator, party, tab or response
    /// information are rejected at admission. They must never be discarded
    /// while keeping the remaining condition as a broader rule.
    struct Condition: Equatable, Sendable {
        var urlFilter: String?
        var regexFilter: String?
        var isURLFilterCaseSensitive: Bool
        var resourceTypes: [String]?
        var excludedResourceTypes: [String]?
        var requestMethods: [String]?
        var excludedRequestMethods: [String]?
        var requestDomains: [String]?
        var excludedRequestDomains: [String]?

        init(
            urlFilter: String? = nil,
            regexFilter: String? = nil,
            isURLFilterCaseSensitive: Bool = false,
            resourceTypes: [String]? = nil,
            excludedResourceTypes: [String]? = nil,
            requestMethods: [String]? = nil,
            excludedRequestMethods: [String]? = nil,
            requestDomains: [String]? = nil,
            excludedRequestDomains: [String]? = nil
        ) {
            self.urlFilter = urlFilter
            self.regexFilter = regexFilter
            self.isURLFilterCaseSensitive = isURLFilterCaseSensitive
            self.resourceTypes = resourceTypes
            self.excludedResourceTypes = excludedResourceTypes
            self.requestMethods = requestMethods
            self.excludedRequestMethods = excludedRequestMethods
            self.requestDomains = requestDomains
            self.excludedRequestDomains = excludedRequestDomains
        }
    }

    let id: Int
    /// Chrome's default when a rule omits it.
    let priority: Int
    let condition: Condition
    let requestHeaders: [HeaderModification]

    init(
        id: Int,
        priority: Int = 1,
        condition: Condition = Condition(),
        requestHeaders: [HeaderModification]
    ) {
        self.id = id
        self.priority = priority
        self.condition = condition
        self.requestHeaders = requestHeaders
    }
}

// MARK: - Wire coding

extension BrowserExtensionEmulatedHeaderRule {
    /// Decodes one rule from the broker payload the compatibility runtime
    /// sends.
    ///
    /// A rule with no usable header operation is rejected rather than stored:
    /// an empty rule would match requests and change nothing, which is
    /// indistinguishable from a bug at the point someone debugs it.
    init(payload: [String: Any]) throws {
        guard let id = Self.integer(payload["id"]), id > 0,
            payload["priority"] == nil || (Self.integer(payload["priority"]) ?? 0) > 0,
            let rawCondition = payload["condition"] as? [String: Any]
        else {
            throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest
        }
        guard let rawHeaders = payload["requestHeaders"] as? [[String: Any]], !rawHeaders.isEmpty
        else {
            throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest
        }
        let headers = try rawHeaders.map(HeaderModification.init(payload:))
        self.init(
            id: id,
            priority: Self.integer(payload["priority"]) ?? 1,
            condition: try Condition(payload: rawCondition),
            requestHeaders: headers
        )
    }

    var payload: [String: Any] {
        [
            "id": id,
            "priority": priority,
            "condition": condition.payload,
            "requestHeaders": requestHeaders.map(\.payload),
        ]
    }

    /// Accepts a JSON integer without accepting `true`/`false`, which bridge
    /// to `NSNumber` too.
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
            number.doubleValue.isFinite,
            number.doubleValue.rounded(.towardZero) == number.doubleValue,
            number.doubleValue >= Double(Int32.min), number.doubleValue <= Double(Int32.max)
        else { return nil }
        return number.intValue
    }

}

extension BrowserExtensionEmulatedHeaderRule.HeaderModification {
    init(payload: [String: Any]) throws {
        guard let header = payload["header"] as? String, !header.isEmpty,
            let rawOperation = payload["operation"] as? String,
            let operation = BrowserExtensionEmulatedHeaderRule.HeaderOperation(
                rawValue: rawOperation)
        else {
            throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest
        }
        let value = payload["value"] as? String
        // Chrome's own validation: a value is required to set or append and
        // forbidden when removing.
        switch operation {
        case .set, .append:
            guard value != nil else {
                throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest
            }
        case .remove:
            break
        }
        self.init(header: header, operation: operation, value: operation == .remove ? nil : value)
    }

    var payload: [String: Any] {
        var result: [String: Any] = ["header": header, "operation": operation.rawValue]
        if let value { result["value"] = value }
        return result
    }
}

extension BrowserExtensionEmulatedHeaderRule.Condition {
    static let supportedKeys: Set<String> = [
        "urlFilter", "regexFilter", "isUrlFilterCaseSensitive", "resourceTypes",
        "excludedResourceTypes", "requestMethods", "excludedRequestMethods",
        "requestDomains", "excludedRequestDomains",
    ]

    init(payload: [String: Any]) throws {
        for key in payload.keys where !Self.supportedKeys.contains(key) {
            throw BrowserExtensionEmulatedHeaderRuleError.unsupportedCondition(key)
        }
        for key in ["urlFilter", "regexFilter"] where payload[key] != nil {
            guard let value = payload[key] as? String, !value.isEmpty,
                value.utf8.allSatisfy({ $0 < 128 })
            else { throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest }
        }
        if let value = payload["isUrlFilterCaseSensitive"] {
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID()
            else { throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest }
        }
        for (include, exclude) in [
            ("urlFilter", "regexFilter"),
            ("resourceTypes", "excludedResourceTypes"),
            ("requestMethods", "excludedRequestMethods"),
        ] {
            guard payload[include] == nil || payload[exclude] == nil
            else { throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest }
        }
        let lists = try Self.validatedLists(payload)
        self.init(
            urlFilter: payload["urlFilter"] as? String,
            regexFilter: payload["regexFilter"] as? String,
            isURLFilterCaseSensitive: (payload["isUrlFilterCaseSensitive"] as? NSNumber)?.boolValue
                ?? false,
            resourceTypes: lists["resourceTypes"],
            excludedResourceTypes: lists["excludedResourceTypes"],
            requestMethods: lists["requestMethods"],
            excludedRequestMethods: lists["excludedRequestMethods"],
            requestDomains: lists["requestDomains"],
            excludedRequestDomains: lists["excludedRequestDomains"]
        )
    }

    private static func validatedLists(_ payload: [String: Any]) throws -> [String: [String]] {
        let resourceTypes: Set<String> = [
            "main_frame", "sub_frame", "stylesheet", "script", "image", "font", "object",
            "xmlhttprequest", "ping", "csp_report", "media", "websocket", "webtransport", "webbundle", "other",
        ]
        let methods: Set<String> = ["connect", "delete", "get", "head", "options", "patch", "post", "put", "other"]
        var result: [String: [String]] = [:]
        for key in [
            "resourceTypes", "excludedResourceTypes", "requestMethods",
            "excludedRequestMethods", "requestDomains", "excludedRequestDomains",
        ] {
            guard let raw = payload[key] else { continue }
            guard let values = raw as? [String], key.hasPrefix("excluded") || !values.isEmpty
            else { throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest }
            for value in values {
                let valid: Bool
                if key.hasSuffix("Domains") {
                    valid = isCanonicalDomain(value)
                } else if key.hasSuffix("Methods") {
                    valid = methods.contains(value)
                } else {
                    valid = resourceTypes.contains(value)
                }
                guard valid else { throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest }
            }
            result[key] = values
        }
        return result
    }

    private static func isCanonicalDomain(_ value: String) -> Bool {
        guard !value.isEmpty, value == value.lowercased(),
            value.utf8.allSatisfy({ $0 < 128 }),
            !value.contains(where: { "/?#@%\\ ".contains($0) }),
            let url = URL(string: "http://\(value)/"), url.host == value, url.port == nil
        else { return false }
        return true
    }

    var payload: [String: Any] {
        var result: [String: Any] = ["isUrlFilterCaseSensitive": isURLFilterCaseSensitive]
        if let urlFilter { result["urlFilter"] = urlFilter }
        if let regexFilter { result["regexFilter"] = regexFilter }
        if let resourceTypes { result["resourceTypes"] = resourceTypes }
        if let excludedResourceTypes { result["excludedResourceTypes"] = excludedResourceTypes }
        if let requestMethods { result["requestMethods"] = requestMethods }
        if let excludedRequestMethods {
            result["excludedRequestMethods"] = excludedRequestMethods
        }
        if let requestDomains { result["requestDomains"] = requestDomains }
        if let excludedRequestDomains { result["excludedRequestDomains"] = excludedRequestDomains }
        return result
    }
}
