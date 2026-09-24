import XCTest

@testable import CrestMobile

@MainActor
final class MobileSavedLocationRestoreActionTests: XCTestCase {
    func testStaleSpaceSelectionCannotRestoreOrNavigateEitherPage() throws {
        let context = makeContext()
        let sourcePage = try XCTUnwrap(context.pages.activePage)
        let sourcePageURL = sourcePage.url
        context.browser.selectSpace(context.destination.id)
        var activationCount = 0
        let action = MobileSavedLocationRestoreAction(
            browser: context.browser,
            pages: context.pages,
            selectTab: { _ in activationCount += 1 }
        )

        let restored = action.perform(context.assignment)

        XCTAssertFalse(restored)
        XCTAssertEqual(activationCount, 0)
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?
                .tabs.first?.url,
            context.awayURL
        )
        XCTAssertEqual(sourcePage.url, sourcePageURL)
    }

    func testExactAssignmentRestoresAndActivatesItsOwnPage() throws {
        let context = makeContext()
        let action = MobileSavedLocationRestoreAction(
            browser: context.browser,
            pages: context.pages,
            selectTab: { tabID in
                context.browser.selectTab(tabID)
                context.pages.select(session: context.browser.presented)
            }
        )

        let restored = action.perform(context.assignment)

        XCTAssertTrue(restored)
        XCTAssertEqual(
            context.browser.session.space(id: context.source.id)?
                .tabs.first?.url,
            context.savedURL
        )
        XCTAssertEqual(context.pages.activePage?.tabID, context.assignment.tabID)
        XCTAssertEqual(context.pages.activePage?.spaceID, context.assignment.spaceID)
        XCTAssertEqual(context.pages.activePage?.profileID, context.assignment.profileID)
    }

    private func makeContext() -> Context {
        let savedURL = URL(string: "about:blank#saved")!
        let awayURL = URL(string: "about:blank#away")!
        let tab = BrowserTab(
            id: TabID(rawValue: Self.uuid(3)),
            title: "Saved",
            url: awayURL,
            savedURL: savedURL,
            placement: .saved
        )
        let source = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(1)),
            profile: BrowsingProfile(id: Self.uuid(2)),
            name: "Source",
            symbol: "1.circle",
            accent: .indigo,
            folders: [],
            tabs: [tab]
        )
        let destinationTab = BrowserTab(
            id: TabID(rawValue: Self.uuid(6)),
            title: "Destination",
            url: URL(string: "about:blank#destination"),
            placement: .current
        )
        let destination = BrowserSpace(
            id: SpaceID(rawValue: Self.uuid(4)),
            profile: BrowsingProfile(id: Self.uuid(5)),
            name: "Destination",
            symbol: "2.circle",
            accent: .teal,
            folders: [],
            tabs: [destinationTab]
        )
        let browser = BrowserStore.hostingPages(
            BrowserSession(spaces: [source, destination]),
            showing: source.id, tabs: [source.id: tab.id, destination.id: destinationTab.id],
            browsingMode: .privateBrowsing
        )
        let pages = MobileBrowserPageStore(
            browser: browser,
            usesEphemeralWebsiteDataStores: true
        )
        pages.select(session: browser.presented)
        return Context(
            browser: browser,
            pages: pages,
            source: source,
            destination: destination,
            assignment: BrowserTabRuntimeAssignment(
                tabID: tab.id,
                spaceID: source.id,
                profileID: source.profile.id
            ),
            savedURL: savedURL,
            awayURL: awayURL
        )
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x53, 0x41, 0x56, 0x45, 0x44, 0x4C, 0x4F, 0x43,
                0x41, 0x54, 0x49, 0x4F, 0x4E, 0x00, 0x00, finalByte
            )
        )
    }

    private struct Context {
        let browser: BrowserStore
        let pages: MobileBrowserPageStore
        let source: BrowserSpace
        let destination: BrowserSpace
        let assignment: BrowserTabRuntimeAssignment
        let savedURL: URL
        let awayURL: URL
    }
}
