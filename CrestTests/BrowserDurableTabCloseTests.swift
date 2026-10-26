import XCTest

@testable import Crest

@MainActor
final class BrowserDurableTabCloseTests: XCTestCase {
    func testDeferredCloseOnlyArchivesAfterApproval() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let original = context.browser.sessionSeed
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(gate.resolve(false))
        XCTAssertEqual(context.browser.sessionSeed, original)
        XCTAssertFalse(context.browser.closeTab(context.tab.id))
        XCTAssertTrue(gate.resolve(true))
        XCTAssertFalse(context.browser.shownSpace!.tabs.contains(context.tab.id))
        XCTAssertTrue(context.browser.shownSpace!.archive.contains(tabID: context.tab.id))
    }

    func testCommandWReturnsSavedAndPinnedTabsHomeBeforeSleepingAfterApproval() throws {
        for placement in [TabPlacement.saved, .pinned] {
            let context = try makeContext(placement: placement, hostingPages: true)
            let browser = context.browser
            let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
            browser.selectTab(context.copy.id)
            pages.select()
            browser.selectTab(context.tab.id)
            pages.select()
            let gate = DeferredDismissal()
            browser.family.pageDismissalAuthorizer = gate
            let commands = BrowserCommandActions(
                browser: browser, pages: pages, chrome: BrowserChromeState(), windows: nil)

            commands.closeTabOrWindow()
            XCTAssertEqual(browser.shownTab?.id, context.tab.id)
            XCTAssertEqual(browser.shownTab?.url, context.tab.savedURL)
            XCTAssertTrue(pages.containsResidentPage(for: context.tab.id))
            XCTAssertNil(gate.pending, "Returning home does not put the page away")

            commands.closeTabOrWindow()
            XCTAssertNotNil(gate.pending)
            XCTAssertFalse(gate.resolve(false))
            XCTAssertEqual(browser.shownTab?.id, context.tab.id)
            commands.closeTabOrWindow()
            XCTAssertTrue(gate.resolve(true))
            XCTAssertEqual(browser.shownTab?.id, context.copy.id)
            XCTAssertFalse(pages.containsResidentPage(for: context.tab.id))
            XCTAssertTrue(browser.shownSpace?.tabs.contains(context.tab.id) == true)
            XCTAssertFalse(browser.shownSpace?.archive.contains(tabID: context.tab.id) == true)
        }
    }

    private final class DeferredDismissal: BrowserPageDismissalAuthorizing {
        var pending: (@MainActor () -> Bool)?
        func performDismissal(
            of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
            operation: @escaping @MainActor () -> Bool
        ) -> Bool {
            pending = operation
            return false
        }
        func resolve(_ allowed: Bool) -> Bool {
            let operation = pending
            pending = nil
            return allowed && operation?() == true
        }
    }

    private func makeContext(placement: TabPlacement, hostingPages: Bool = false) throws -> Context {
        let root = try XCTUnwrap(URL(string: "http://127.0.0.1:1/root"))
        let child = try XCTUnwrap(URL(string: "http://127.0.0.1:1/child"))
        let tab = TabState.Seed(title: "Durable", url: child, savedURL: root, placement: placement)
        let copy = TabState.Seed(title: "Independent copy", url: child, placement: .current)
        let archived = [
            ArchivedTabState.Seed(
                tab: TabState.Seed(title: "Archive", url: child, placement: .current), archivedAt: .now,
                reason: .closed)
        ]
        let space = SpaceState.Seed(
            name: "Test", symbol: "circle", accent: .indigo,
            folders: [], tabs: [tab, copy], archivedTabs: archived
        )
        let seed = SessionState.Seed(spaces: [space])
        let browser =
            hostingPages
            ? BrowserStore.hostingPages(seed, showing: space.id, tabs: [space.id: tab.id])
            : BrowserStore(seed: seed, showing: space.id, tabs: [space.id: tab.id])
        return Context(
            browser: browser, tab: tab, copy: copy, archived: archived,
            assignment: BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
        )
    }

    private struct Context {
        let browser: BrowserStore
        let tab: TabState.Seed
        let copy: TabState.Seed
        let archived: [ArchivedTabState.Seed]
        let assignment: BrowserTabRuntimeAssignment
    }
}
