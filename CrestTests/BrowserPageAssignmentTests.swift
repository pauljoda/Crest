import XCTest

@testable import Crest

@MainActor
final class BrowserPageAssignmentTests: XCTestCase {
    func testCurrentSelectionRequiresACompletePresentedRuntime() throws {
        let session = BrowserSession.preview
        let pool = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        XCTAssertFalse(pool.isPresentingSelection(in: session))

        pool.select(session: session)
        XCTAssertTrue(pool.isPresentingSelection(in: session))

        let space = try XCTUnwrap(session.selectedSpace)
        let replacement = BrowserSpace(
            id: space.id, profile: BrowsingProfile(), name: space.name,
            symbol: space.symbol, accent: space.accent, folders: space.folders,
            tabs: space.tabs, selectedTabID: space.selectedTabID
        )
        let differentProfile = BrowserSession(
            spaces: [replacement], selectedSpaceID: replacement.id
        )
        XCTAssertFalse(pool.isPresentingSelection(in: differentProfile))

        pool.deactivatePagePresentation()
        XCTAssertFalse(pool.isPresentingSelection(in: session))
        pool.reconcile(validTabIDs: [])
    }

    func testCurrentSelectionRejectsChangedSplitMembershipAndFocus() {
        let group = SplitGroupID()
        let first = BrowserTab(title: "First", url: nil, placement: .current, splitGroupID: group)
        let second = BrowserTab(title: "Second", url: nil, placement: .current, splitGroupID: group)
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Split",
            symbol: "circle", accent: .indigo, folders: [],
            tabs: [first, second], selectedTabID: first.id
        )
        var session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        let pool = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        pool.select(session: session)
        XCTAssertTrue(pool.isPresentingSelection(in: session))

        session.spaces[0].selectedTabID = second.id
        XCTAssertFalse(pool.isPresentingSelection(in: session))
        session.spaces[0].selectedTabID = first.id
        session.spaces[0].tabs.reverse()
        XCTAssertFalse(pool.isPresentingSelection(in: session))
        session.spaces[0].tabs = [first]
        XCTAssertFalse(pool.isPresentingSelection(in: session))
        pool.reconcile(validTabIDs: [])
    }

    func testPreparingAnExtensionSelectionStillOwesItsInitialNavigation() throws {
        var session = BrowserSession.preview
        let spaceIndex = try XCTUnwrap(
            session.spaces.firstIndex {
                $0.id == session.selectedSpaceID
            })
        let tabIndex = try XCTUnwrap(
            session.spaces[spaceIndex].tabs.firstIndex {
                $0.id == session.spaces[spaceIndex].selectedTabID
            })
        session.spaces[spaceIndex].tabs[tabIndex].url = try XCTUnwrap(
            URL(string: "about:blank#extension-preparation")
        )
        let pool = BrowserPagePool(usesEphemeralWebsiteDataStores: true)

        pool.prepareExtensionSelection(session: session)
        XCTAssertFalse(pool.isPresentingSelection(in: session))

        pool.select(session: session)
        XCTAssertTrue(pool.isPresentingSelection(in: session))
        pool.reconcile(validTabIDs: [])
    }

    func testActivePageMatchingRequiresTheExactTabSpaceAndProfileAssignment() throws {
        let session = BrowserSession.preview
        let tab = try XCTUnwrap(session.selectedTab)
        let space = try XCTUnwrap(session.selectedSpace)
        let pool = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        pool.select(session: session)
        let page = try XCTUnwrap(pool.activePage)

        XCTAssertTrue(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            ) === page
        )
        XCTAssertNil(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: TabID(rawValue: UUID()),
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            )
        )
        XCTAssertNil(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: SpaceID(rawValue: UUID()),
                    profileID: space.profile.id
                )
            )
        )
        XCTAssertNil(
            pool.activePage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: tab.id,
                    spaceID: space.id,
                    profileID: UUID()
                )
            )
        )
    }

    /// A split card binds a page it did not select, so the same drift guard the
    /// focused path uses has to hold for every member — including the unfocused
    /// ones, which is the case `activePage(matching:)` cannot answer at all.
    func testPresentedPageMatchingGuardsEveryCardsSpaceAndProfile() throws {
        let groupID = SplitGroupID()
        let members = try (1...2).map { index in
            BrowserTab(
                title: "Member \(index)",
                url: try XCTUnwrap(URL(string: "https://split.crest.test/\(index)")),
                placement: .current,
                splitGroupID: groupID
            )
        }
        let outsider = BrowserTab(title: "Outsider", url: nil, placement: .current)
        let space = BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: "Split",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: members + [outsider],
            selectedTabID: members[0].id
        )
        let pool = BrowserPagePool(usesEphemeralWebsiteDataStores: true)
        pool.select(tab: members[0], space: space)

        for member in members {
            let assignment = BrowserTabRuntimeAssignment(
                tabID: member.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
            XCTAssertTrue(
                pool.presentedPage(matching: assignment)
                    === pool.presentedPage(for: member.id),
                "Every card resolves its own page, focused or not."
            )
            XCTAssertNil(
                pool.presentedPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: member.id,
                        spaceID: SpaceID(),
                        profileID: space.profile.id
                    )
                )
            )
            XCTAssertNil(
                pool.presentedPage(
                    matching: BrowserTabRuntimeAssignment(
                        tabID: member.id,
                        spaceID: space.id,
                        profileID: UUID()
                    )
                )
            )
        }
        XCTAssertNil(
            pool.presentedPage(
                matching: BrowserTabRuntimeAssignment(
                    tabID: outsider.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            ),
            "A tab outside the presented group has no card to bind."
        )

        pool.reconcile(validTabIDs: [])
    }
}
