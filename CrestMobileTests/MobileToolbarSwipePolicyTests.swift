import XCTest

@testable import CrestMobile

@MainActor
final class MobileToolbarSwipePolicyTests: XCTestCase {
    func testShippedModePagesCardsAndDoesNothingOutsideASplit() {
        XCTAssertEqual(MobileToolbarSwipePolicy.mode, .cardsOnly)
        XCTAssertEqual(
            MobileToolbarSwipePolicy.destination(isInSplitGroup: true),
            .adjacentCard
        )
        XCTAssertEqual(
            MobileToolbarSwipePolicy.destination(isInSplitGroup: false),
            .none,
            """
            The toolbar swipe no longer switches Spaces. Spaces move through the \
            tab viewer's switcher and the ⌥⌘←/→ chords.
            """
        )
    }

}
