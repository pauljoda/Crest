import Foundation

/// The disposable double behind `BrowserExtensionDeclarativeNetRequestPersisting`.
///
/// Isolated validation launches and tests use it so a fixture run cannot leave
/// an extension's dynamic rules behind in the installed profile.
@MainActor
final class InMemoryBrowserExtensionDeclarativeNetRequestStore:
    BrowserExtensionDeclarativeNetRequestPersisting
{
    private var rules: [BrowserExtensionServiceClientID: [BrowserExtensionEmulatedHeaderRule]] = [:]

    init(rules: [BrowserExtensionServiceClientID: [BrowserExtensionEmulatedHeaderRule]] = [:]) {
        self.rules = rules
    }

    func loadDynamicRules(for client: BrowserExtensionServiceClientID)
        -> [BrowserExtensionEmulatedHeaderRule]
    {
        rules[client] ?? []
    }

    func saveDynamicRules(
        _ rules: [BrowserExtensionEmulatedHeaderRule], for client: BrowserExtensionServiceClientID
    ) {
        self.rules[client] = rules
    }
}
