import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteActionPolicyTests: XCTestCase {
    func testEmptySelectionActionsRejectChangedSelectionSpaceProfileAndLock() throws {
        let source = makeSpace(index: 1)
        let target = try assignment(for: source)
        let other = makeSpace(index: 2)
        let browser = makeBrowser(spaces: [source, other], showing: source.id)
        var selectionCount = 0
        let actions = BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: source), browser: browser,
            accessController: BrowserSpaceAccessController(), didSelectTab: { selectionCount += 1 })
        XCTAssertTrue(actions.isAvailable)
        XCTAssertFalse(actions.selectTab(try assignment(for: other)))

        func assertUnavailable(line: UInt = #line) {
            let session = browser.session
            let window = browser.window
            XCTAssertFalse(actions.isAvailable, line: line)
            XCTAssertFalse(actions.selectTab(target), line: line)
            XCTAssertFalse(actions.openURL(URL(string: "about:blank")!), line: line)
            XCTAssertEqual(browser.session, session, line: line)
            XCTAssertEqual(browser.window, window, line: line)
        }

        // The window chose a tab in the source Space.
        browser.activateSessionTab(target.tabID, in: source.id)
        assertUnavailable()
        browser.clearPresentedTabSelection(in: source.id)
        XCTAssertTrue(actions.isAvailable)

        // The window moved to another Space.
        browser.selectPresentedSpace(other.id)
        assertUnavailable()
        browser.selectPresentedSpace(source.id)
        browser.clearPresentedTabSelection(in: source.id)
        XCTAssertTrue(actions.isAvailable)

        // Its profile was replaced.
        browser.replaceProfileForTesting(of: source.id, with: uuid(0xF0))
        assertUnavailable()
        // It has its profile back, but asks for authentication.
        browser.replaceProfileForTesting(of: source.id, with: source.profile.id)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: source.id)
        assertUnavailable()
        // It is gone.
        browser.removeSpaceForTesting(source.id)
        assertUnavailable()
        XCTAssertEqual(selectionCount, 0)
    }

    func testTargetRequiresCurrentSpaceAndRejectsReplacementOrLock() throws {
        let source = makeSpace(index: 1)
        let destination = makeSpace(index: 2)
        let sourceAssignment = try assignment(for: source)
        let browser = makeBrowser(
            spaces: [source, destination], showing: source.id, tabs: [source.id: sourceAssignment.tabID])
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

        browser.replaceProfileForTesting(of: source.id, with: uuid(0xF0))

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

        browser.replaceProfileForTesting(of: source.id, with: source.profile.id)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: source.id)
        let protectedSource = try XCTUnwrap(browser.session.space(id: source.id))
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
        showing spaceID: SpaceID,
        tabs: [SpaceID: TabID] = [:]
    ) -> BrowserStore {
        BrowserStore(session: BrowserSession(spaces: spaces), showing: spaceID, tabs: tabs)
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
