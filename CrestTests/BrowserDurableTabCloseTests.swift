import XCTest

@testable import Crest

@MainActor
final class BrowserDurableTabCloseTests: XCTestCase {
    func testMissingAndUnknownPreferencesResumeAndChosenPolicyPersists() throws {
        let name = "crest.tests.durable-close.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(BrowserDurableTabPreferenceStore(defaults: defaults).closePolicy, .resumeLastLocation)
        defaults.set("unknown-future-policy", forKey: BrowserDurableTabPreferenceStore.key)
        XCTAssertEqual(BrowserDurableTabPreferenceStore(defaults: defaults).closePolicy, .resumeLastLocation)
        let preferences = BrowserDurableTabPreferenceStore(defaults: defaults)
        preferences.closePolicy = .returnToSavedURL
        XCTAssertEqual(BrowserDurableTabPreferenceStore(defaults: defaults).closePolicy, .returnToSavedURL)
    }

    func testCloseResumesByDefaultAndResetPersistsWithoutChangingDurableIdentity() throws {
        for placement: TabPlacement in [.pinned, .saved] {
            for policy in BrowserDurableTabClosePolicy.allCases {
                let context = try makeContext(placement: placement)
                let preferences = BrowserDurableTabPreferenceStore()
                preferences.closePolicy = policy
                var discardedState: Bool?
                let action = BrowserDurableTabCloseAction(
                    browser: context.browser,
                    spaceAccess: BrowserSpaceAccessController(),
                    preferences: preferences,
                    closePage: { assignment, discardState in
                        XCTAssertEqual(assignment, context.assignment)
                        discardedState = discardState
                        return true
                    }
                )

                XCTAssertTrue(action.perform(context.assignment))

                let closed = try XCTUnwrap(context.browser.selectedSpace?.tabs.first)
                var expected = context.tab
                if policy == .returnToSavedURL { expected.url = expected.savedSiteURL }
                XCTAssertEqual(closed, expected)
                XCTAssertEqual(discardedState, policy == .returnToSavedURL)
                XCTAssertNil(context.browser.selectedTab)
                XCTAssertEqual(context.persistence.session?.selectedSpace?.tabs.first, expected)
                XCTAssertEqual(context.browser.selectedSpace?.tabs.last, context.copy)
                XCTAssertEqual(context.browser.selectedSpace?.archivedTabs, context.archived)
            }
        }
    }

    func testStaleLockedAndOrdinaryTabsDoNotCloseOrDiscardState() throws {
        for placement: TabPlacement in [.current, .pinned, .saved] {
            let context = try makeContext(placement: placement)
            var closeCount = 0
            let action = BrowserDurableTabCloseAction(
                browser: context.browser,
                spaceAccess: BrowserSpaceAccessController(),
                preferences: BrowserDurableTabPreferenceStore(),
                closePage: { _, _ in
                    closeCount += 1
                    return true
                }
            )
            let original = context.browser.session
            let stale = BrowserTabRuntimeAssignment(
                tabID: context.tab.id, spaceID: context.assignment.spaceID, profileID: UUID()
            )
            XCTAssertFalse(action.perform(stale))
            if placement == .current { XCTAssertFalse(action.perform(context.assignment)) }
            XCTAssertEqual(context.browser.session, original)

            var locked = try XCTUnwrap(context.browser.selectedSpace)
            locked.accessPolicy = .deviceOwnerAuthentication
            context.browser.session = BrowserSession(spaces: [locked], selectedSpaceID: locked.id)
            XCTAssertFalse(action.perform(context.assignment))
            XCTAssertEqual(closeCount, 0)
        }
    }

    func testMismatchedResidentPageLeavesTheSessionUntouched() throws {
        let context = try makeContext(placement: .saved)
        let preferences = BrowserDurableTabPreferenceStore()
        preferences.closePolicy = .returnToSavedURL
        let original = context.browser.session
        let action = BrowserDurableTabCloseAction(
            browser: context.browser, spaceAccess: BrowserSpaceAccessController(),
            preferences: preferences, closePage: { _, _ in false }
        )
        XCTAssertFalse(action.perform(context.assignment))
        XCTAssertEqual(context.browser.session, original)
    }

    private func makeContext(placement: TabPlacement) throws -> Context {
        let root = try XCTUnwrap(URL(string: "https://example.com/root"))
        let child = try XCTUnwrap(URL(string: "https://example.com/child"))
        let tab = BrowserTab(title: "Durable", url: child, savedURL: root, placement: placement)
        let copy = BrowserTab(title: "Independent copy", url: child, placement: .current)
        let archived = [
            ArchivedTab(
                tab: BrowserTab(title: "Archive", url: child, placement: .current), archivedAt: .now, reason: .closed)
        ]
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [tab, copy], archivedTabs: archived, selectedTabID: tab.id
        )
        let persistence = InMemoryBrowserSessionPersistence()
        let browser = BrowserStore(
            session: BrowserSession(spaces: [space], selectedSpaceID: space.id), persistence: persistence
        )
        return Context(
            browser: browser, persistence: persistence, tab: tab, copy: copy, archived: archived,
            assignment: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profile.id)
        )
    }

    private struct Context {
        let browser: BrowserStore
        let persistence: InMemoryBrowserSessionPersistence
        let tab: BrowserTab
        let copy: BrowserTab
        let archived: [ArchivedTab]
        let assignment: BrowserTabRuntimeAssignment
    }
}
