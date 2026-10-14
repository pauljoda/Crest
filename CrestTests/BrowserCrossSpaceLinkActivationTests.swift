import XCTest

@testable import Crest

/// Explicit cross-Space link opening must survive the native Space-entry policy.
@MainActor
final class BrowserCrossSpaceLinkActivationTests: XCTestCase {
    // MARK: - Actions - Link Destinations

    func testOpeningALinkInAnotherSpaceKeepsTheNewTabActiveThroughSpaceEntry() throws {
        let sourceTab = TabState.Seed(
            title: "Source", url: URL(string: "https://source.crest.test"), placement: .current)
        let source = SpaceState.Seed(name: "Source", symbol: "circle", accent: .indigo, folders: [], tabs: [sourceTab])
        let destination = SpaceState.Seed(name: "Destination", symbol: "circle", accent: .rose, folders: [], tabs: [])
        let browser = BrowserStore.hostingPages(
            SessionState.Seed(spaces: [source, destination]), showing: source.id, tabs: [source.id: sourceTab.id])
        let pages = BrowserPagePool(browser: browser, usesEphemeralWebsiteDataStores: true)
        defer { pages.reconcile(validTabIDs: []) }
        let access = BrowserSpaceAccessController()
        browser.attachSpaceAccess(access)
        let host = BrowserLinkDestinationHost(browser: browser, spaceAccess: access)
        let from = BrowserTabRuntimeAssignment(tabID: sourceTab.id, spaceID: source.id, profileID: source.profileID)
        let to = BrowserSpaceRuntimeAssignment(space: destination)
        let address = try XCTUnwrap(URL(string: "https://destination.crest.test/article"))

        XCTAssertTrue(host.openLink(address, from: from, in: to))
        let opened = try XCTUnwrap(browser.shownTab?.id)
        pages.selectSpace(in: browser)

        XCTAssertEqual(browser.selectedSpaceID, destination.id)
        XCTAssertEqual(browser.shownTab?.id, opened)
        XCTAssertEqual(browser.shownTab?.address, address)
        XCTAssertEqual(pages.activePage?.spaceID, destination.id)
        XCTAssertEqual(pages.activePage?.profileID, destination.profileID)
        XCTAssertEqual(browser.spaceModel(source.id)?.tabs.values.map(\.seed), source.tabs)
        XCTAssertEqual(browser.core.state.windows[browser.windowID]?.shownTabIDs.contains(opened), true)
    }

    func testOpeningALinkRejectsAReplacedDestinationProfileWithoutChangingSelection() throws {
        let tab = TabState.Seed(title: "Source", url: URL(string: "https://source.crest.test"), placement: .current)
        let source = SpaceState.Seed(name: "Source", symbol: "circle", accent: .indigo, folders: [], tabs: [tab])
        let destination = SpaceState.Seed(name: "Destination", symbol: "circle", accent: .rose, folders: [], tabs: [])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [source, destination]), showing: source.id,
            tabs: [source.id: tab.id])
        let access = BrowserSpaceAccessController()
        browser.attachSpaceAccess(access)
        let host = BrowserLinkDestinationHost(browser: browser, spaceAccess: access)
        let from = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: source.id, profileID: source.profileID)
        let stale = BrowserSpaceRuntimeAssignment(space: destination)
        browser.replaceProfileForTesting(of: destination.id, with: UUID())
        let before = browser.sessionSeed

        XCTAssertFalse(
            host.openLink(try XCTUnwrap(URL(string: "https://destination.crest.test")), from: from, in: stale))

        XCTAssertEqual(browser.sessionSeed, before)
        XCTAssertEqual(browser.selectedSpaceID, source.id)
        XCTAssertEqual(browser.shownTab?.id, tab.id)
    }

}
