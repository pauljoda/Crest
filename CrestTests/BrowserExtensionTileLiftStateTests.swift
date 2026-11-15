import XCTest

@testable import Crest

/// A carried pinned extension tile moves to the slot it is let go on, the
/// strip keeps that order until the engine reports it, and a carry whose tile
/// leaves the strip ends instead of holding every tile's click.
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

    // MARK: - Actions - Dropping

    func testLettingGoMovesTheTileBeforeItsNewNeighbour() throws {
        let state = carrying("alpha")
        state.update(pointer: CGPoint(x: 140, y: 50), gapIndex: 1)
        let move = try XCTUnwrap(state.drop(landingAt: tile))
        XCTAssertEqual(move.extensionID, "alpha")
        XCTAssertEqual(move.beforeID, "charlie")
    }

    func testLettingGoAtTheEndMovesTheTileBeforeNone() throws {
        let state = carrying("alpha")
        state.update(pointer: CGPoint(x: 170, y: 50), gapIndex: 2)
        let move = try XCTUnwrap(state.drop(landingAt: tile))
        XCTAssertEqual(move.extensionID, "alpha")
        XCTAssertNil(move.beforeID)
    }

    func testLettingGoWhereItCameFromMovesNothing() {
        let state = carrying("bravo")
        XCTAssertNil(state.drop(landingAt: tile))
        XCTAssertEqual(state.shownOrder(order, profileID: profileID), order)
    }

    /// The engine saves the order a moment later, and the strip must not show
    /// the old one in between.
    func testTheStripKeepsTheDroppedOrderUntilTheEngineReportsIt() {
        let state = carrying("alpha")
        state.update(pointer: CGPoint(x: 170, y: 50), gapIndex: 2)
        _ = state.drop(landingAt: tile)
        XCTAssertEqual(state.shownOrder(order, profileID: profileID), ["bravo", "charlie", "alpha"])
        XCTAssertEqual(state.shownOrder(order, profileID: UUID()), order)
        state.engineReported(["bravo", "charlie", "alpha"], profileID: profileID)
        XCTAssertEqual(state.shownOrder(order, profileID: profileID), order)
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

    func testACarryEndsWhenTheStripCanNoLongerBeReordered() {
        let state = carrying("alpha")
        state.stripChanged(to: order, in: spaceID, isReorderable: false)
        XCTAssertNil(state.lift)
    }

    func testAnotherSpacesStripLeavesTheCarryBe() {
        let state = carrying("alpha")
        state.stripChanged(to: ["bravo"], in: UUID(), isReorderable: true)
        XCTAssertTrue(state.isCarrying)
        state.stripChanged(to: order, in: spaceID, isReorderable: true)
        XCTAssertTrue(state.isCarrying)
    }
}
