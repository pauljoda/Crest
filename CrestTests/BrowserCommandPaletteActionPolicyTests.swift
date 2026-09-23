import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteActionPolicyTests: XCTestCase {
    func testEmptySelectionActionsRejectChangedSelectionSpaceProfileAndLock() throws {
        let source = makeSpace(index: 1)
        let target = try assignment(for: source)
        let other = makeSpace(index: 2)
        let browser = makeBrowser(
            spaces: [source, other], selection: BrowserStoreSelection(selectedSpaceID: source.id))
        var selectionCount = 0
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: source), browser: browser,
            accessController: BrowserSpaceAccessController(), didSelectTab: { selectionCount += 1 })
        XCTAssertTrue(actions.isAvailable)
        XCTAssertFalse(actions.selectTab(try assignment(for: other)))

        func assertUnavailable(line: UInt = #line) {
            let session = browser.session
            let selection = browser.selection
            XCTAssertFalse(actions.isAvailable, line: line)
            XCTAssertFalse(actions.selectTab(target), line: line)
            XCTAssertFalse(actions.openURL(URL(string: "about:blank")!), line: line)
            XCTAssertEqual(browser.session, session, line: line)
            XCTAssertEqual(browser.selection, selection, line: line)
        }

        // The window chose a tab in the source Space.
        browser.presentTab(target.tabID, in: source.id)
        assertUnavailable()
        browser.clearPresentedTabSelection(in: source.id)
        XCTAssertTrue(actions.isAvailable)

        // The window moved to another Space.
        browser.selectPresentedSpace(other.id)
        assertUnavailable()
        browser.selectPresentedSpace(source.id)
        browser.clearPresentedTabSelection(in: source.id)
        XCTAssertTrue(actions.isAvailable)

        var lockedSource = source
        lockedSource.accessPolicy = .deviceOwnerAuthentication
        for session in [
            BrowserSession(spaces: [replacingProfile(in: source), other]),
            BrowserSession(spaces: [lockedSource, other]),
            BrowserSession(spaces: [other]),
        ] {
            browser.session = session
            assertUnavailable()
        }
        XCTAssertEqual(selectionCount, 0)
    }

    func testTargetRequiresCurrentSpaceAndRejectsReplacementOrLock() throws {
        let source = makeSpace(index: 1)
        let destination = makeSpace(index: 2)
        let sourceAssignment = try assignment(for: source)
        let browser = makeBrowser(
            spaces: [source, destination],
            selection: BrowserStoreSelection(
                selectedSpaceID: source.id, selectedTabIDsBySpace: [source.id: sourceAssignment.tabID]))
        let access = BrowserSpaceAccessController()
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

        browser.session = BrowserSession(spaces: [replacingProfile(in: source), destination])

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
        browser.session = BrowserSession(spaces: [protectedSource, destination])
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
        selection: BrowserStoreSelection
    ) -> BrowserStore {
        BrowserStore(
            session: BrowserSession(spaces: spaces),
            selection: selection,
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
            tabs: [tab]
        )
    }

    private func assignment(
        for space: BrowserSpace
    ) throws -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: try XCTUnwrap(space.tabs.first?.id),
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
            savedTabsExpansionModifiedAt: space.savedTabsExpansionModifiedAt
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
