import XCTest

@testable import Crest

final class BrowserFreshInstallSeedTests: XCTestCase {
    func testFreshInstallStartsWithOneDisposablePersonalSpace() throws {
        let session = BrowserSession.freshInstallSeed
        let space = try XCTUnwrap(session.spaces.first)

        XCTAssertEqual(session.spaces.count, 1)
        XCTAssertEqual(session.selectedSpaceID, space.id)
        XCTAssertEqual(space.name, "Personal")
        XCTAssertEqual(space.tabs.count, 1)
        XCTAssertEqual(space.selectedTabID, space.tabs.first?.id)
        XCTAssertTrue(try XCTUnwrap(space.tabs.first).isStartPage)
        XCTAssertTrue(space.pinnedTabs.isEmpty)
        XCTAssertTrue(space.savedTabs.isEmpty)
        XCTAssertNotNil(session.disposableSeedMarker)
    }

}
