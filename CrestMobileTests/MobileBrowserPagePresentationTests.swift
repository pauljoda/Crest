import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPagePresentationTests: XCTestCase {
    func testCompactPageActionsExposeOnlyTheSelectedRuntimeAssignment() throws {
        let firstTab = BrowserTab(
            title: "First",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let secondTab = BrowserTab(
            title: "Second",
            url: URL(string: "about:blank"),
            placement: .current
        )
        let firstSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "First Space",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [firstTab]
        )
        let secondSpace = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Second Space",
            symbol: "2.circle",
            accent: .teal,
            folders: [],
            tabs: [secondTab]
        )
        let browser = BrowserStore.hostingPages(
            BrowserSession(spaces: [firstSpace, secondSpace]),
            showing: firstSpace.id, tabs: [firstSpace.id: firstTab.id, secondSpace.id: secondTab.id]
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )
        pages.select(session: browser.presented)
        let firstPage = try XCTUnwrap(pages.activePage)
        let firstPort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: BrowserSpaceAccessController(),
            expectedAssignment: assignment(tab: firstTab, space: firstSpace)
        )

        XCTAssertTrue(firstPort.isAvailable)
        XCTAssertTrue(firstPort.activePage === firstPage)
        XCTAssertEqual(firstPort.activeURL, firstTab.url)

        browser.selectSpace(secondSpace.id)
        let secondPort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: BrowserSpaceAccessController(),
            expectedAssignment: assignment(tab: secondTab, space: secondSpace)
        )

        XCTAssertFalse(firstPort.isAvailable)
        XCTAssertNil(firstPort.pageAssignment)
        XCTAssertNil(firstPort.activePage)
        XCTAssertNil(firstPort.activeURL)
        XCTAssertFalse(firstPort.canGoBack)
        XCTAssertFalse(firstPort.canGoForward)
        XCTAssertTrue(firstPort.backHistory.isEmpty)
        XCTAssertTrue(firstPort.forwardHistory.isEmpty)
        XCTAssertFalse(firstPort.copyPageLink())
        firstPort.presentFind()
        XCTAssertTrue(pages.activePage === firstPage)
        XCTAssertFalse(firstPage.isFindPresented)

        XCTAssertFalse(secondPort.isAvailable)
        XCTAssertNil(secondPort.activePage)
        XCTAssertNil(secondPort.activeURL)
        XCTAssertFalse(secondPort.copyPageLinkAsMarkdown())

        pages.select(session: browser.presented)
        let secondPage = try XCTUnwrap(pages.activePage)
        XCTAssertTrue(secondPort.isAvailable)
        XCTAssertTrue(secondPort.activePage === secondPage)
        secondPort.presentFind()
        XCTAssertTrue(secondPage.isFindPresented)
        XCTAssertFalse(firstPage.isFindPresented)

        let wrongProfilePort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            spaceAccess: BrowserSpaceAccessController(),
            expectedAssignment: BrowserTabRuntimeAssignment(
                tabID: secondTab.id,
                spaceID: secondSpace.id,
                profileID: UUID()
            )
        )
        XCTAssertFalse(wrongProfilePort.isAvailable)
        XCTAssertNil(wrongProfilePort.activePage)
    }

    private func assignment(
        tab: BrowserTab,
        space: BrowserSpace
    ) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: tab.id,
            spaceID: space.id,
            profileID: space.profile.id
        )
    }
}
