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

    func testReplacementProfileWithTheSameSpaceIDCannotReuseTheOldAction() throws {
        let context = makeContext()
        let replacement = replacingProfile(
            in: context.source,
            with: Self.uuid(9)
        )
        let sourceIndex = try XCTUnwrap(
            context.browser.session.spaces.firstIndex {
                $0.id == context.source.id
            }
        )
        context.browser.session.spaces[sourceIndex] = replacement
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
            context.browser.session.space(id: replacement.id)?
                .tabs.first?.url,
            context.awayURL
        )
        XCTAssertEqual(context.pages.activePage?.profileID, context.source.profile.id)
    }

    func testExactAssignmentRestoresAndActivatesItsOwnPage() throws {
        let context = makeContext()
        let action = MobileSavedLocationRestoreAction(
            browser: context.browser,
            pages: context.pages,
            selectTab: { tabID in
                context.browser.selectTab(tabID)
                context.pages.select(session: context.browser.session)
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
            tabs: [tab],
            selectedTabID: tab.id
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
            tabs: [destinationTab],
            selectedTabID: destinationTab.id
        )
        let browser = BrowserStore(
            session: BrowserSession(
                spaces: [source, destination],
                selectedSpaceID: source.id
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
        let pages = MobileBrowserPageStore(
            usesEphemeralWebsiteDataStores: true
        )
        pages.select(session: browser.session)
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

    private func replacingProfile(
        in space: BrowserSpace,
        with profileID: UUID
    ) -> BrowserSpace {
        BrowserSpace(
            id: space.id,
            profile: BrowsingProfile(id: profileID),
            name: space.name,
            symbol: space.symbol,
            accent: space.accent,
            branding: space.branding,
            folders: space.folders,
            tabs: space.tabs,
            archivedTabs: space.archivedTabs,
            history: space.history,
            browsingPreferences: space.browsingPreferences,
            credentialPreferences: space.credentialPreferences,
            accessPolicy: space.accessPolicy,
            isSavedTabsExpanded: space.isSavedTabsExpanded,
            savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt,
            selectedTabID: space.selectedTabID
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
