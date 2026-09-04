import Foundation

/// Both writable rulesets for one extension in one Space.
struct BrowserExtensionEmulatedHeaderRulesets: Equatable, Sendable {
    var session: [BrowserExtensionEmulatedHeaderRule]
    var dynamic: [BrowserExtensionEmulatedHeaderRule]

    init(
        session: [BrowserExtensionEmulatedHeaderRule] = [],
        dynamic: [BrowserExtensionEmulatedHeaderRule] = []
    ) {
        self.session = session
        self.dynamic = dynamic
    }

    subscript(ruleset: BrowserExtensionEmulatedHeaderRuleset) -> [BrowserExtensionEmulatedHeaderRule]
    {
        get {
            switch ruleset {
            case .session: session
            case .dynamic: dynamic
            }
        }
        set {
            switch ruleset {
            case .session: session = newValue
            case .dynamic: dynamic = newValue
            }
        }
    }

    var isEmpty: Bool { session.isEmpty && dynamic.isEmpty }
}

/// The app-side seam for the header operations WebKit refuses.
///
/// The rules are set by the extension's worker and read by its side panel,
/// popup, options page, and offscreen documents, so they cannot live in any
/// one JavaScript context. They are shared per extension *and* Space: two
/// Spaces run two WebKit extension contexts with separate storage, and a rule
/// set in one must not reach the other.
@MainActor
protocol BrowserExtensionDeclarativeNetRequestHandling: AnyObject {
    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID)
    /// Chrome clears session rules when an extension's context unloads or
    /// reloads and keeps dynamic rules; so does this.
    func unregister(client: BrowserExtensionServiceClientID)

    func rulesets(for client: BrowserExtensionServiceClientID, in spaceID: SpaceID)
        -> BrowserExtensionEmulatedHeaderRulesets
    func setRules(
        _ rules: [BrowserExtensionEmulatedHeaderRule],
        ruleset: BrowserExtensionEmulatedHeaderRuleset,
        for client: BrowserExtensionServiceClientID,
        in spaceID: SpaceID
    )

    func events(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionEmulatedHeaderRulesets>
}

/// Dynamic rules outlive the browser session, so one adapter stores them and
/// an in-memory double stands in for tests, previews, and isolated launches.
@MainActor
protocol BrowserExtensionDeclarativeNetRequestPersisting {
    func loadDynamicRules(for client: BrowserExtensionServiceClientID)
        -> [BrowserExtensionEmulatedHeaderRule]
    func saveDynamicRules(
        _ rules: [BrowserExtensionEmulatedHeaderRule], for client: BrowserExtensionServiceClientID)
}
