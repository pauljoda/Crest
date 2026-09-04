import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionDeclarativeNetRequestStoreTests: XCTestCase {
    private let claude = BrowserExtensionServiceClientID("claude.space.personal")!
    private let chatgpt = BrowserExtensionServiceClientID("chatgpt.space.personal")!

    private func rule(
        id: Int, header: String = "anthropic-client-platform", value: String = "ext"
    ) -> BrowserExtensionEmulatedHeaderRule {
        BrowserExtensionEmulatedHeaderRule(
            id: id,
            condition: .init(urlFilter: "https://api.anthropic.com/*"),
            requestHeaders: [.init(header: header, operation: .set, value: value)]
        )
    }

    func testARulesetIsReplacedWholesaleAndTheTwoRulesetsAreIndependent() {
        let store = BrowserExtensionDeclarativeNetRequestStore(
            persistence: InMemoryBrowserExtensionDeclarativeNetRequestStore())
        let space = SpaceID()
        store.register(client: claude, spaceID: space)

        store.setRules([rule(id: 1), rule(id: 2)], ruleset: .session, for: claude, in: space)
        XCTAssertEqual(store.rulesets(for: claude, in: space).session.map(\.id), [1, 2])
        XCTAssertTrue(store.rulesets(for: claude, in: space).dynamic.isEmpty)

        // The runtime applies `removeRuleIds` itself and sends the result, so a
        // replacement is the only write.
        store.setRules([rule(id: 2, value: "updated")], ruleset: .session, for: claude, in: space)
        XCTAssertEqual(store.rulesets(for: claude, in: space).session.map(\.id), [2])
        XCTAssertEqual(
            store.rulesets(for: claude, in: space).session.first?.requestHeaders.first?.value,
            "updated")

        store.setRules([rule(id: 9)], ruleset: .dynamic, for: claude, in: space)
        XCTAssertEqual(store.rulesets(for: claude, in: space).session.map(\.id), [2])
        XCTAssertEqual(store.rulesets(for: claude, in: space).dynamic.map(\.id), [9])

        store.setRules([], ruleset: .session, for: claude, in: space)
        XCTAssertTrue(store.rulesets(for: claude, in: space).session.isEmpty)
        XCTAssertEqual(store.rulesets(for: claude, in: space).dynamic.map(\.id), [9])
    }

    func testOneExtensionCannotSeeAnothersTableAndNeitherCanAnotherSpace() {
        let store = BrowserExtensionDeclarativeNetRequestStore(
            persistence: InMemoryBrowserExtensionDeclarativeNetRequestStore())
        let personal = SpaceID()
        let work = SpaceID()
        store.register(client: claude, spaceID: personal)
        store.register(client: chatgpt, spaceID: personal)

        store.setRules([rule(id: 1)], ruleset: .session, for: claude, in: personal)
        XCTAssertTrue(store.rulesets(for: chatgpt, in: personal).session.isEmpty)
        // The same extension in a second Space is a second WebKit context with
        // its own storage; its rules do not cross.
        XCTAssertTrue(store.rulesets(for: claude, in: work).session.isEmpty)
    }

    func testUnloadingAContextClearsSessionRulesAndKeepsDynamicOnes() {
        let persistence = InMemoryBrowserExtensionDeclarativeNetRequestStore()
        let store = BrowserExtensionDeclarativeNetRequestStore(persistence: persistence)
        let space = SpaceID()
        store.register(client: claude, spaceID: space)
        store.setRules([rule(id: 1)], ruleset: .session, for: claude, in: space)
        store.setRules([rule(id: 2)], ruleset: .dynamic, for: claude, in: space)

        store.unregister(client: claude)
        XCTAssertTrue(store.rulesets(for: claude, in: space).session.isEmpty)
        XCTAssertEqual(store.rulesets(for: claude, in: space).dynamic.map(\.id), [2])
    }

    func testDynamicRulesSurviveARelaunchThroughTheDefaultsAdapter() throws {
        let suiteName = "BrowserExtensionDeclarativeNetRequestStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let space = SpaceID()

        let first = BrowserExtensionDeclarativeNetRequestStore(
            persistence: UserDefaultsBrowserExtensionDeclarativeNetRequestStore(defaults: defaults))
        first.register(client: claude, spaceID: space)
        first.setRules([rule(id: 1)], ruleset: .session, for: claude, in: space)
        first.setRules(
            [
                BrowserExtensionEmulatedHeaderRule(
                    id: 5, priority: 3,
                    condition: .init(
                        urlFilter: "https://api.anthropic.com/*", isURLFilterCaseSensitive: true,
                        resourceTypes: ["xmlhttprequest", "other"]),
                    requestHeaders: [
                        .init(header: "anthropic-client-version", operation: .set, value: "1.2.3"),
                        .init(header: "x-drop", operation: .remove),
                    ])
            ], ruleset: .dynamic, for: claude, in: space)

        let relaunched = BrowserExtensionDeclarativeNetRequestStore(
            persistence: UserDefaultsBrowserExtensionDeclarativeNetRequestStore(defaults: defaults))
        relaunched.register(client: claude, spaceID: space)
        let restored = relaunched.rulesets(for: claude, in: space)
        XCTAssertTrue(restored.session.isEmpty)
        XCTAssertEqual(restored.dynamic.count, 1)
        XCTAssertEqual(restored.dynamic[0].id, 5)
        XCTAssertEqual(restored.dynamic[0].priority, 3)
        XCTAssertTrue(restored.dynamic[0].condition.isURLFilterCaseSensitive)
        XCTAssertEqual(restored.dynamic[0].condition.resourceTypes, ["xmlhttprequest", "other"])
        XCTAssertEqual(restored.dynamic[0].requestHeaders.map(\.operation), [.set, .remove])

        relaunched.setRules([], ruleset: .dynamic, for: claude, in: space)
        let cleared = BrowserExtensionDeclarativeNetRequestStore(
            persistence: UserDefaultsBrowserExtensionDeclarativeNetRequestStore(defaults: defaults))
        cleared.register(client: claude, spaceID: space)
        XCTAssertTrue(cleared.rulesets(for: claude, in: space).dynamic.isEmpty)
    }

    func testEveryContextOfTheSameExtensionIsToldAndNoOtherExtensionIs() async {
        let store = BrowserExtensionDeclarativeNetRequestStore(
            persistence: InMemoryBrowserExtensionDeclarativeNetRequestStore())
        let space = SpaceID()
        store.register(client: claude, spaceID: space)
        store.register(client: chatgpt, spaceID: space)
        var worker = store.events(for: claude).makeAsyncIterator()
        var panel = store.events(for: claude).makeAsyncIterator()
        var outsider = store.events(for: chatgpt).makeAsyncIterator()

        store.setRules([rule(id: 1)], ruleset: .session, for: claude, in: space)
        let workerRulesets = await worker.next()
        let panelRulesets = await panel.next()
        XCTAssertEqual(workerRulesets?.session.map(\.id), [1])
        XCTAssertEqual(panelRulesets?.session.map(\.id), [1])

        // A write that changes nothing publishes nothing, so the next event the
        // other extension's stream yields is its own.
        store.setRules([rule(id: 1)], ruleset: .session, for: claude, in: space)
        store.setRules([rule(id: 4)], ruleset: .dynamic, for: chatgpt, in: space)
        let outsiderRulesets = await outsider.next()
        XCTAssertEqual(outsiderRulesets?.dynamic.map(\.id), [4])
        XCTAssertTrue(outsiderRulesets?.session.isEmpty == true)
    }
}
