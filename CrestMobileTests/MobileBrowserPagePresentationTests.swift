import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserPagePresentationTests: XCTestCase {
    func testCompactUnloadedPageRestoresWhileRegularPageRemainsUnloaded() {
        XCTAssertEqual(
            presentation(isCompact: true),
            .automaticRestore
        )
        XCTAssertEqual(
            presentation(isCompact: false),
            .unloaded
        )
    }

    func testMobileFailurePrecedenceMatchesMacPresentation() {
        XCTAssertEqual(
            presentation(
                isCompact: true,
                hasActivePage: true,
                hasNavigationFailure: true,
                hasProcessFailure: true
            ),
            .navigationFailure
        )
        XCTAssertEqual(
            presentation(
                isCompact: true,
                hasActivePage: true,
                hasProcessFailure: true
            ),
            .processFailure
        )
        XCTAssertEqual(
            presentation(isCompact: true, hasActivePage: true),
            .livePage
        )
    }

    func testNoSelectionNeverRestoresOrPresentsAResidentPage() {
        XCTAssertEqual(
            presentation(
                isCompact: true,
                selection: .none,
                hasActivePage: true,
                hasNavigationFailure: true,
                hasProcessFailure: true
            ),
            .noSelection
        )
    }

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
            id: SpaceID(rawValue: UUID()),
            profile: BrowsingProfile(),
            name: "First Space",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [firstTab],
            selectedTabID: firstTab.id
        )
        let secondSpace = BrowserSpace(
            id: SpaceID(rawValue: UUID()),
            profile: BrowsingProfile(),
            name: "Second Space",
            symbol: "2.circle",
            accent: .teal,
            folders: [],
            tabs: [secondTab],
            selectedTabID: secondTab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [firstSpace, secondSpace],
                selectedSpaceID: firstSpace.id
            ),
            persistence: InMemoryBrowserSessionPersistence()
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        pages.select(session: browser.session)
        let firstPage = try XCTUnwrap(pages.activePage)
        let firstPort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            expectedAssignment: assignment(tab: firstTab, space: firstSpace)
        )

        XCTAssertTrue(firstPort.isAvailable)
        XCTAssertTrue(firstPort.activePage === firstPage)
        XCTAssertEqual(firstPort.activeURL, firstTab.url)

        browser.selectSpace(secondSpace.id)
        let secondPort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
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

        pages.select(session: browser.session)
        let secondPage = try XCTUnwrap(pages.activePage)
        XCTAssertTrue(secondPort.isAvailable)
        XCTAssertTrue(secondPort.activePage === secondPage)
        secondPort.presentFind()
        XCTAssertTrue(secondPage.isFindPresented)
        XCTAssertFalse(firstPage.isFindPresented)

        let wrongProfilePort = MobileSelectedPageActionPort(
            browser: browser,
            pages: pages,
            expectedAssignment: BrowserTabRuntimeAssignment(
                tabID: secondTab.id,
                spaceID: secondSpace.id,
                profileID: UUID()
            )
        )
        XCTAssertFalse(wrongProfilePort.isAvailable)
        XCTAssertNil(wrongProfilePort.activePage)
    }

    private func presentation(
        isCompact: Bool,
        selection: BrowserPagePresentationSelection = .webPage,
        hasActivePage: Bool = false,
        hasNavigationFailure: Bool = false,
        hasProcessFailure: Bool = false
    ) -> BrowserPagePresentation {
        BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: selection,
                hasActivePage: hasActivePage,
                hasNavigationFailure: hasNavigationFailure,
                hasProcessFailure: hasProcessFailure,
                unloadedBehavior: isCompact
                    ? .restoreAutomatically
                    : .remainUnloaded
            )
        )
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
