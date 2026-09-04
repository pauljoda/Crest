import Foundation

/// The decoded wire request behind one emulated-header-rule broker call.
///
/// The runtime owns the remove/add arithmetic — it has to, because it is the
/// side that answers `getSessionRules` — so the broker never receives a delta.
/// `dnr.setEmulatedHeaderRules` carries the whole ruleset the extension
/// believes it has, and replaces Crest's copy with it.
struct BrowserExtensionDeclarativeNetRequestBrokerRequest {
    enum Operation: String, CaseIterable, Sendable {
        /// `{api, ruleset, rules}` → `{ok: true}`.
        case setRules = "dnr.setEmulatedHeaderRules"
        /// `{api}` → `{rulesets: {session, dynamic}}`.
        case rules = "dnr.emulatedHeaderRules"
    }

    /// Either permission publishes `chrome.declarativeNetRequest` in Chrome,
    /// so either one is enough to reach the emulation behind it.
    static let requiredCapabilities: Set<String> = [
        "declarativeNetRequest",
        "declarativeNetRequestWithHostAccess",
    ]

    let operation: Operation
    let ruleset: BrowserExtensionEmulatedHeaderRuleset?
    let rules: [BrowserExtensionEmulatedHeaderRule]

    init(message: [String: Any]) throws {
        guard let api = message["api"] as? String, let operation = Operation(rawValue: api) else {
            throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest
        }
        self.operation = operation
        switch operation {
        case .setRules:
            guard let rawRuleset = message["ruleset"] as? String,
                let ruleset = BrowserExtensionEmulatedHeaderRuleset(rawValue: rawRuleset),
                let rawRules = message["rules"] as? [[String: Any]]
            else {
                throw BrowserExtensionEmulatedHeaderRuleError.invalidRequest
            }
            self.ruleset = ruleset
            rules = try rawRules.map(BrowserExtensionEmulatedHeaderRule.init(payload:))
        case .rules:
            ruleset = nil
            rules = []
        }
    }
}
