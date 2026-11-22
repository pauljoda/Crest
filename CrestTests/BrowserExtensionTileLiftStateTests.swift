import XCTest

@testable import Crest

/// A carry whose pinned extension tile leaves the strip ends instead of
/// holding every tile's click.
@MainActor
final class BrowserExtensionTileLiftStateTests: XCTestCase {
    // MARK: - Variables

    private let spaceID = UUID()
    private let profileID = UUID()
    private let order = ["alpha", "bravo", "charlie"]
    private let tile = CGRect(x: 100, y: 40, width: 24, height: 24)

    // MARK: - Actions - Fixtures

    private func carrying(_ extensionID: String) -> BrowserExtensionTileLiftState {
        let state = BrowserExtensionTileLiftState()
        state.begin(
            extensionID: extensionID, spaceID: spaceID, profileID: profileID, icon: nil, frame: tile,
            pointer: CGPoint(x: 110, y: 50), order: order)
        return state
    }

    // MARK: - Actions - Ending

    /// The carried tile's drag never hears its release once the tile leaves,
    /// so the carry must end with it rather than hold every tile's click.
    func testACarryEndsWhenItsTileLeavesTheStrip() {
        let state = carrying("alpha")
        state.stripChanged(to: ["bravo", "charlie"], in: spaceID, isReorderable: true)
        XCTAssertNil(state.lift)
        XCTAssertFalse(state.suppressesActivation)
    }
}
