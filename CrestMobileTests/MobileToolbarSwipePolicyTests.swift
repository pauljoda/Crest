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

    func testContextualModeRemainsAvailableAsTheDocumentedFutureSlot() {
        XCTAssertEqual(
            MobileToolbarSwipePolicy.destination(
                isInSplitGroup: true,
                mode: .contextual
            ),
            .adjacentCard,
            "Cards win inside a group in every mode."
        )
        XCTAssertEqual(
            MobileToolbarSwipePolicy.destination(
                isInSplitGroup: false,
                mode: .contextual
            ),
            .adjacentSpace
        )
    }

    func testEveryModeAndDestinationStaysAccountedFor() {
        XCTAssertEqual(
            MobileToolbarSwipeMode.allCases,
            [.cardsOnly, .contextual]
        )
        XCTAssertEqual(
            Set(
                MobileToolbarSwipeMode.allCases.flatMap { mode in
                    [true, false].map {
                        MobileToolbarSwipePolicy.destination(
                            isInSplitGroup: $0,
                            mode: mode
                        )
                    }
                }
            ),
            Set(MobileToolbarSwipeDestination.allCases),
            "Every destination the enum offers is reachable from some mode."
        )
    }

    func testRecognizerThresholdsAreUnchangedByTheNewRouting() {
        // The gesture itself is untouched: BrowserSpaceSwipePolicy still decides
        // whether a drag counts and which way it points, and only the routing
        // above it changed.
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(for: CGSize(width: -90, height: 12)),
            .next
        )
        XCTAssertEqual(
            BrowserSpaceSwipePolicy.direction(for: CGSize(width: 90, height: -8)),
            .previous
        )
        XCTAssertNil(
            BrowserSpaceSwipePolicy.direction(for: CGSize(width: 60, height: 0))
        )
    }
}
