import Foundation

/// Dynamic emulated header rules, stored as the same JSON the wire carries.
///
/// The rule payload is Chrome's own vocabulary, so what is written here is
/// what `getDynamicRules` hands back — no second representation to keep in
/// step. A ruleset is a handful of small objects; there is no reason for it to
/// leave `UserDefaults`.
@MainActor
final class UserDefaultsBrowserExtensionDeclarativeNetRequestStore:
    BrowserExtensionDeclarativeNetRequestPersisting
{
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    func loadDynamicRules(for client: BrowserExtensionServiceClientID)
        -> [BrowserExtensionEmulatedHeaderRule]
    {
        guard let data = defaults.data(forKey: key(for: client)),
            let payloads = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }
        // A rule that no longer decodes is dropped rather than failing the
        // load: the rest of the ruleset is still what the extension set.
        return payloads.compactMap { try? BrowserExtensionEmulatedHeaderRule(payload: $0) }
    }

    func saveDynamicRules(
        _ rules: [BrowserExtensionEmulatedHeaderRule], for client: BrowserExtensionServiceClientID
    ) {
        guard !rules.isEmpty else {
            defaults.removeObject(forKey: key(for: client))
            return
        }
        let payloads = rules.map(\.payload)
        guard JSONSerialization.isValidJSONObject(payloads),
            let data = try? JSONSerialization.data(withJSONObject: payloads)
        else { return }
        defaults.set(data, forKey: key(for: client))
    }

    private func key(for client: BrowserExtensionServiceClientID) -> String {
        "extension.declarativeNetRequest.dynamic-header-rules.\(client.rawValue)"
    }
}
