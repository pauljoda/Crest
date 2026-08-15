import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserCommandPaletteActionPolicyTests: XCTestCase {
    func testExactSourceAndTargetAssignmentsRejectReplacementLockAndDeletion() throws {
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

        var protectedDestination = destination
        protectedDestination.accessPolicy = .deviceOwnerAuthentication
        browser.session = BrowserSession(
            spaces: [source, protectedDestination],
            selectedSpaceID: source.id
        )
        XCTAssertNil(
            BrowserCommandPaletteActionPolicy.target(
                try assignment(for: protectedDestination),
                from: sourceAssignment,
                in: browser,
                accessController: access
            )
        )
    }

    func testOtherSpacesExcludeLockedAndDeletingDestinations() throws {
        let source = makeSpace(index: 10)
        let available = makeSpace(index: 20)
        var locked = makeSpace(index: 30)
        locked.accessPolicy = .deviceOwnerAuthentication
        let browser = makeBrowser(
            spaces: [source, available, locked],
            selected: source.id
        )
        let access = BrowserSpaceAccessController()

        XCTAssertEqual(
            BrowserCommandPaletteActionPolicy.availableOtherSpaces(
                from: try assignment(for: source),
                in: browser,
                accessController: access
            ).map(\.id),
            [available.id]
        )

        XCTAssertTrue(browser.family.beginDeletingSpace(available.id))
        XCTAssertTrue(
            BrowserCommandPaletteActionPolicy.availableOtherSpaces(
                from: try assignment(for: source),
                in: browser,
                accessController: access
            ).isEmpty
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
