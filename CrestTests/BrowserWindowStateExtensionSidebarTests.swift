import Foundation
import XCTest

@testable import Crest

final class BrowserWindowStateExtensionSidebarTests: XCTestCase {
    func testSidebarPreferencesRoundTripWithoutPersistingOpenState() throws {
        let spaceID = SpaceID()
        var state = BrowserWindowState(selectedSpaceID: spaceID, selectedTabIDsBySpace: [:])
        let preferences = BrowserExtensionSidebarWindowState(
            lastClientID: try XCTUnwrap(BrowserExtensionServiceClientID("chatgpt")), width: 380
        )
        state.captureExtensionSidebar(preferences, for: spaceID)
        let encoded = try JSONEncoder().encode(state)
        XCTAssertEqual(try JSONDecoder().decode(BrowserWindowState.self, from: encoded), state)
        XCTAssertEqual(state.extensionSidebarBySpace?[spaceID], preferences)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("isOpen"))
    }

    func testOlderWindowStateStillDecodesAndUnknownSpacesArePruned() throws {
        let space = BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Work",
            symbol: "briefcase", accent: .indigo, folders: [], tabs: [], selectedTabID: nil
        )
        let session = BrowserSession(spaces: [space], selectedSpaceID: space.id)
        var state = BrowserWindowState(restoring: session)
        let old = try JSONEncoder().encode(state)
        XCTAssertNil(try JSONDecoder().decode(BrowserWindowState.self, from: old).extensionSidebarBySpace)
        state.captureExtensionSidebar(.init(width: 400), for: SpaceID())
        state.repair(using: session)
        XCTAssertNil(state.extensionSidebarBySpace)
    }
}
