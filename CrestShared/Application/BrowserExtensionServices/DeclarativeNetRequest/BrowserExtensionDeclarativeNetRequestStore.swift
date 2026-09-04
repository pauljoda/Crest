import Foundation
import Observation

/// The emulated `modifyHeaders` request-header table every context of one
/// extension shares.
///
/// WebKit rejects a `modifyHeaders` rule outright when any header name is not
/// on its accepted list, so a package that sets a custom header loses the
/// whole rule — including the standard headers in it. The compatibility
/// runtime keeps the acceptable half native and hands the rest here, and every
/// extension context reads this table back before it makes a request.
///
/// The table is keyed by extension *and* Space, not by extension alone: Crest
/// runs one WebKit extension context per Space with separate storage, and a
/// rule set in one Space has no business reaching another.
@Observable
@MainActor
final class BrowserExtensionDeclarativeNetRequestStore:
    BrowserExtensionDeclarativeNetRequestHandling
{
    private struct Scope: Hashable {
        let client: BrowserExtensionServiceClientID
        let spaceID: SpaceID
    }

    /// Bumped on every accepted change so a future extensions surface can show
    /// what a package is rewriting without the store publishing its internals.
    private(set) var revision = 0

    @ObservationIgnored private var rulesetsByScope: [Scope: BrowserExtensionEmulatedHeaderRulesets] =
        [:]
    @ObservationIgnored private var spacesByClient: [BrowserExtensionServiceClientID: SpaceID] = [:]
    @ObservationIgnored private let persistence: any BrowserExtensionDeclarativeNetRequestPersisting
    @ObservationIgnored private let eventHub = BrowserExtensionDeclarativeNetRequestEventHub()

    init(persistence: any BrowserExtensionDeclarativeNetRequestPersisting) {
        self.persistence = persistence
    }

    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID) {
        spacesByClient[client] = spaceID
        let scope = Scope(client: client, spaceID: spaceID)
        guard rulesetsByScope[scope] == nil else { return }
        // Chrome's dynamic rules survive a relaunch. Reading them at
        // registration means the first `getDynamicRules` after launch answers
        // with what the extension last set rather than an empty table.
        rulesetsByScope[scope] = BrowserExtensionEmulatedHeaderRulesets(
            dynamic: persistence.loadDynamicRules(for: client)
        )
    }

    func unregister(client: BrowserExtensionServiceClientID) {
        eventHub.remove(client: client)
        guard let spaceID = spacesByClient.removeValue(forKey: client) else { return }
        let scope = Scope(client: client, spaceID: spaceID)
        guard var rulesets = rulesetsByScope[scope] else { return }
        // Session rules die with the context, exactly as they do in Chrome.
        // Dynamic rules stay, both here and on disk.
        guard !rulesets.session.isEmpty else { return }
        rulesets.session = []
        rulesetsByScope[scope] = rulesets
        revision &+= 1
    }

    func rulesets(for client: BrowserExtensionServiceClientID, in spaceID: SpaceID)
        -> BrowserExtensionEmulatedHeaderRulesets
    {
        rulesetsByScope[Scope(client: client, spaceID: spaceID)]
            ?? BrowserExtensionEmulatedHeaderRulesets(
                dynamic: persistence.loadDynamicRules(for: client))
    }

    func setRules(
        _ rules: [BrowserExtensionEmulatedHeaderRule],
        ruleset: BrowserExtensionEmulatedHeaderRuleset,
        for client: BrowserExtensionServiceClientID,
        in spaceID: SpaceID
    ) {
        let scope = Scope(client: client, spaceID: spaceID)
        var current =
            rulesetsByScope[scope]
            ?? BrowserExtensionEmulatedHeaderRulesets(
                dynamic: persistence.loadDynamicRules(for: client))
        guard current[ruleset] != rules else { return }
        current[ruleset] = rules
        rulesetsByScope[scope] = current
        if ruleset == .dynamic {
            persistence.saveDynamicRules(rules, for: client)
        }
        revision &+= 1
        eventHub.publish(current, to: client)
    }

    func events(for client: BrowserExtensionServiceClientID)
        -> AsyncStream<BrowserExtensionEmulatedHeaderRulesets>
    {
        eventHub.events(for: client)
    }
}
