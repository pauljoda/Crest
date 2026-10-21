import XCTest

@testable import Crest

/// How a held Most Recent Tab shortcut reads keys and the release of its
/// modifiers: which of them switch, which only highlight, which cancel, and
/// which never reach the page.
final class RecentTabSwitcherSessionTests: XCTestCase {
    private let items = (0..<5).map { _ in RecentTabItem(tabIDs: [UUID()], focusedTabID: UUID()) }
    private let controlTab = BrowserShortcut(key: .special(.tab), modifiers: .control)
    private let controlShiftTab = BrowserShortcut(key: .special(.tab), modifiers: [.control, .shift])

    private func session(
        _ direction: RecentTabSwitchDirection = .forward, binding: BrowserShortcut? = nil,
        other: BrowserShortcut? = nil, count: Int = 5
    ) throws -> RecentTabSwitcherSession {
        try XCTUnwrap(
            RecentTabSwitcherSession(
                direction: direction, binding: binding ?? (direction == .forward ? controlTab : controlShiftTab),
                otherBinding: other ?? (direction == .forward ? controlShiftTab : controlTab),
                items: Array(items.prefix(count))))
    }

    func testQuickTapJumpsToTheSecondItemForwardAndTheLastBackward() throws {
        let forward = try session(.forward)
        XCTAssertEqual(forward.modifiersChanged(to: []), .commit(items[1]))
        let backward = try session(.backward)
        XCTAssertEqual(backward.modifiersChanged(to: []), .commit(items[4]))
    }

    func testQuickTapWithOnlyTheCurrentTabDoesNothing() throws {
        let single = try session(count: 1)
        XCTAssertEqual(single.modifiersChanged(to: []), .cancel)
    }

    func testReleasingShiftAloneKeepsHolding() throws {
        let backward = try session(.backward)
        XCTAssertNil(backward.modifiersChanged(to: .control))
    }

    func testTabAndShiftTabMoveAndWrap() throws {
        var held = try session(.forward)
        for _ in 0..<4 { _ = held.keyDown(controlTab) }
        XCTAssertEqual(held.highlightedIndex, 0)
        XCTAssertTrue(held.isShowing)
        XCTAssertEqual(held.keyDown(controlShiftTab), .init(isConsumed: true, outcome: nil))
        XCTAssertEqual(held.highlightedIndex, 4)
    }

    func testBackwardStartsAtTheOldestAndShiftTabKeepsGoingBack() throws {
        var held = try session(.backward)
        XCTAssertEqual(held.highlightedIndex, 4)
        _ = held.keyDown(controlShiftTab)
        XCTAssertEqual(held.highlightedIndex, 3)
        _ = held.keyDown(controlTab)
        XCTAssertEqual(held.highlightedIndex, 4)
    }

    func testNumberKeysHighlightWithoutSwitching() throws {
        var held = try session()
        let response = held.keyDown(BrowserShortcut(key: .character("4"), modifiers: .control))
        XCTAssertEqual(response, .init(isConsumed: true, outcome: nil))
        XCTAssertEqual(held.highlightedIndex, 3)
        XCTAssertEqual(held.modifiersChanged(to: []), .commit(items[3]))
    }

    func testReturnSwitchesAndEscapeCancels() throws {
        var returning = try session()
        _ = returning.keyDown(controlTab)
        XCTAssertEqual(
            returning.keyDown(BrowserShortcut(key: .special(.returnKey), modifiers: .control)).outcome,
            .commit(items[2]))
        var escaping = try session()
        XCTAssertEqual(
            escaping.keyDown(BrowserShortcut(key: .special(.escape), modifiers: .control)),
            .init(isConsumed: true, outcome: .cancel))
    }

    func testArrowsMoveTheHighlight() throws {
        var held = try session()
        _ = held.keyDown(BrowserShortcut(key: .special(.rightArrow), modifiers: .control))
        XCTAssertEqual(held.highlightedIndex, 2)
        _ = held.keyDown(BrowserShortcut(key: .special(.leftArrow), modifiers: .control))
        XCTAssertEqual(held.highlightedIndex, 1)
    }

    func testKeysReachThePageUntilThePanelShows() throws {
        var held = try session()
        let letter = BrowserShortcut(key: .character("c"), modifiers: .control)
        XCTAssertFalse(held.keyDown(letter).isConsumed)
        XCTAssertNil(held.showDelayElapsed(modifiers: .control))
        XCTAssertTrue(held.keyDown(letter).isConsumed)
    }

    func testAMissedReleaseEndsTheHoldOnTheNextKey() throws {
        var held = try session()
        let response = held.keyDown(BrowserShortcut(key: .character("c"), modifiers: .command))
        XCTAssertEqual(response, .init(isConsumed: false, outcome: .commit(items[1])))
    }

    func testACustomBindingHoldsItsOwnModifiersAndReversesWithShift() throws {
        let commandE = BrowserShortcut(key: .character("e"), modifiers: .command)
        var held = try session(.forward, binding: commandE, other: nil)
        XCTAssertEqual(held.heldModifiers, .command)
        _ = held.keyDown(commandE)
        XCTAssertEqual(held.highlightedIndex, 2)
        _ = held.keyDown(BrowserShortcut(key: .character("e"), modifiers: [.command, .shift]))
        XCTAssertEqual(held.highlightedIndex, 1)
        XCTAssertNil(held.modifiersChanged(to: [.command, .shift]))
        XCTAssertEqual(held.modifiersChanged(to: .shift), .commit(items[1]))
    }

    func testABindingWithNothingToHoldBeginsNoSession() {
        let shiftF5 = BrowserShortcut(key: .special(.f5), modifiers: .shift)
        XCTAssertNil(
            RecentTabSwitcherSession(direction: .forward, binding: shiftF5, otherBinding: nil, items: items))
    }

    func testRefreshKeepsTheHighlightOnTheSameTabAndEmptyCancels() throws {
        var held = try session()
        _ = held.keyDown(controlTab)
        let highlighted = items[2]
        XCTAssertNil(held.refresh(items: [items[0], items[2], items[3]]))
        XCTAssertEqual(held.highlightedItem, highlighted)
        XCTAssertEqual(held.refresh(items: []), .cancel)
    }
}
