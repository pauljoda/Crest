import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteActionPolicyTests: XCTestCase {
    func testEmptySelectionActionsRejectChangedSelectionSpaceProfileAndLock() throws {
        var source = makeSpace(index: 1)
        let target = try assignment(for: source)
        source.selectedTabID = nil
        let other = makeSpace(index: 2)
        let browser = makeBrowser(spaces: [source, other], selected: source.id)
        var selectionCount = 0
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: source), browser: browser,
            accessController: BrowserSpaceAccessController(), didSelectTab: { selectionCount += 1 })
        XCTAssertTrue(actions.isAvailable)
        XCTAssertFalse(actions.selectTab(try assignment(for: other)))

        var selectedSource = source
        selectedSource.selectedTabID = target.tabID
        var lockedSource = source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        let unavailableSessions = [
            BrowserSession(spaces: [selectedSource, other], selectedSpaceID: source.id),
            BrowserSession(spaces: [source, other], selectedSpaceID: other.id),
            BrowserSession(spaces: [replacingProfile(in: source), other], selectedSpaceID: source.id),
            BrowserSession(spaces: [lockedSource, other], selectedSpaceID: source.id),
            BrowserSession(spaces: [other], selectedSpaceID: other.id),
        ]
        for session in unavailableSessions {
            browser.session = session
            XCTAssertFalse(actions.isAvailable)
            XCTAssertFalse(actions.selectTab(target))
            XCTAssertFalse(actions.openURL(URL(string: "about:blank")!))
            XCTAssertEqual(browser.session, session)
        }
        XCTAssertEqual(selectionCount, 0)
    }

    func testTargetRequiresCurrentSpaceAndRejectsReplacementOrLock() throws {
        let source = makeSpace(index: 1)
        let destination = makeSpace(index: 2)
        let browser = makeBrowser(spaces: [source, destination], selected: source.id)
        let access = BrowserSpaceAccessController()
        let sourceAssignment = try assignment(for: source)
        let destinationAssignment = try assignment(for: destination)

        XCTAssertTrue(
            BrowserCommandPaletteActionPolicy.isSourceAvailable(
                sourceAssignment,
                in: browser,
                accessController: access
            )
        )
        XCTAssertNotNil(
            BrowserCommandPaletteActionPolicy.target(
                sourceAssignment,
                from: sourceAssignment,
                in: browser,
                accessController: access
            )
        )
        XCTAssertNil(
            BrowserCommandPaletteActionPolicy.target(
                destinationAssignment,
                from: sourceAssignment,
                in: browser,
                accessController: access
            )
        )

        browser.session = BrowserSession(
            spaces: [replacingProfile(in: source), destination],
            selectedSpaceID: source.id
        )

        XCTAssertFalse(
            BrowserCommandPaletteActionPolicy.isSourceAvailable(
                sourceAssignment,
                in: browser,
                accessController: access
            )
        )
        XCTAssertNil(
            BrowserCommandPaletteActionPolicy.target(
                destinationAssignment,
                from: sourceAssignment,
                in: browser,
                accessController: access
            )
        )

        var protectedSource = source
        protectedSource.accessPolicy = .deviceOwnerAuthentication
        browser.session = BrowserSession(
            spaces: [protectedSource, destination],
            selectedSpaceID: source.id
        )
        XCTAssertNil(
            BrowserCommandPaletteActionPolicy.target(
                try assignment(for: protectedSource),
                from: sourceAssignment,
                in: browser,
                accessController: access
            )
        )
    }

    private func makeBrowser(
        spaces: [BrowserSpace],
        selected: SpaceID
    ) -> BrowserStore {
        BrowserStore(
            session: BrowserSession(spaces: spaces, selectedSpaceID: selected),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
        )
    }

    private func makeSpace(index: UInt8) -> BrowserSpace {
        let tab = BrowserTab(
            id: TabID(rawValue: uuid(index &+ 1)),
            title: "Tab \(index)",
            url: URL(fileURLWithPath: "/palette-\(index)"),
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(rawValue: uuid(index &+ 2)),
            profile: BrowsingProfile(id: uuid(index &+ 3)),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func assignment(
        for space: BrowserSpace
    ) throws -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(space.selectedTabID),
            spaceID: space.id,
            profileID: space.profile.id
        )
    }

    private func replacingProfile(in space: BrowserSpace) -> BrowserSpace {
        BrowserSpace(
            id: space.id,
            profile: BrowsingProfile(id: uuid(0xF0)),
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

    private func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x43, 0x52, 0x45, 0x53,
                0x54, 0x50,
                0x41, 0x4C,
                0x45, 0x54,
                0x54, 0x45, 0x54, 0x45, 0x53, finalByte
            ))
    }
}
