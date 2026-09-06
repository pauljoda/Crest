import XCTest

@testable import CrestMobile

@MainActor
final class MobileDurableTabCloseTests: XCTestCase {
    func testCommandsApplyClosePolicyToPinnedAndSavedTabsWithoutReloadingThem() throws {
        let preferences = BrowserDurableTabPreferenceStore.shared
        let previousPolicy = preferences.closePolicy
        defer { preferences.closePolicy = previousPolicy }
        for placement: TabPlacement in [.pinned, .saved] {
            for policy in BrowserDurableTabClosePolicy.allCases {
                let context = try makeContext(placement: placement)
                defer { context.pages.reconcile(validTabIDs: []) }
                preferences.closePolicy = policy
                context.pages.select(session: context.browser.session)
                let commands = MobileBrowserCommandController(browser: context.browser, pages: context.pages)

                XCTAssertEqual(commands.dismissSelectedTab(), context.tab.id)

                let closed = try XCTUnwrap(context.browser.selectedSpace?.tabs.first)
                XCTAssertEqual(closed.id, context.tab.id)
                XCTAssertEqual(closed.savedURL, context.tab.savedURL)
                XCTAssertEqual(closed.url, policy == .returnToSavedURL ? context.tab.savedURL : context.tab.url)
                XCTAssertNil(context.browser.selectedTab)
                XCTAssertNil(context.pages.activePage)
                XCTAssertFalse(context.pages.containsResidentPage(for: context.tab.id))
                XCTAssertTrue(try XCTUnwrap(context.browser.selectedSpace).archivedTabs.isEmpty)
            }
        }
    }

    func testRawUnloadKeepsChildLocationEvenWhenClosePolicyReturnsToRoot() throws {
        let preferences = BrowserDurableTabPreferenceStore.shared
        let previousPolicy = preferences.closePolicy
        defer { preferences.closePolicy = previousPolicy }
        preferences.closePolicy = .returnToSavedURL
        let context = try makeContext(placement: .saved)
        defer { context.pages.reconcile(validTabIDs: []) }
        context.pages.select(session: context.browser.session)

        context.pages.unloadPage(for: context.tab.id)

        XCTAssertEqual(context.browser.selectedTab, context.tab)
        XCTAssertFalse(context.pages.containsResidentPage(for: context.tab.id))
    }

    func testLockedSpaceCommandCannotResetOrCloseItsDurableTab() throws {
        let context = try makeContext(placement: .saved)
        defer { context.pages.reconcile(validTabIDs: []) }
        var space = try XCTUnwrap(context.browser.selectedSpace)
        space.accessPolicy = .deviceOwnerAuthentication
        context.browser.session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let original = context.browser.session
        let commands = MobileBrowserCommandController(browser: context.browser, pages: context.pages)
        XCTAssertNil(commands.dismissSelectedTab())
        XCTAssertEqual(context.browser.session, original)
    }

    private func makeContext(placement: TabPlacement) throws -> Context {
        let tab = BrowserTab(
            title: "Durable", url: try XCTUnwrap(URL(string: "about:blank#child")),
            savedURL: try XCTUnwrap(URL(string: "about:blank#root")), placement: placement
        )
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [tab], selectedTabID: tab.id
        )
        return Context(
            browser: BrowserStore(
                session: BrowserSession(spaces: [space], selectedSpaceID: space.id),
                persistence: InMemoryBrowserSessionPersistence()
            ),
            pages: MobileBrowserPageStore(usesEphemeralWebsiteDataStores: true), tab: tab
        )
    }

    private struct Context {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let tab: BrowserTab
    }
}
