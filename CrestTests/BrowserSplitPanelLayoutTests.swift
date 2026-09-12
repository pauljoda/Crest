import XCTest

@testable import Crest

final class BrowserSplitPanelLayoutTests: XCTestCase {
    private let gap = BrowserSplitLayoutMetrics.interCardGap

    func testPanelDoesNotProduceNegativeOrNonFiniteWidths() {
        XCTAssertEqual(
            BrowserSplitPanelLayout.resolvedWidth(
                requestedWidth: 360, containerWidth: 100, memberCount: 4
            ), 0)
        XCTAssertEqual(
            BrowserSplitPanelLayout.resolvedWidth(
                requestedWidth: 360, containerWidth: .nan, memberCount: 1
            ), 0)
        XCTAssertEqual(
            BrowserSplitPanelLayout.resolvedWidth(
                requestedWidth: 360, containerWidth: 1000, memberCount: 0
            ), 0)
    }

    func testPanelResizeUsesTotalSemanticTravelAndCommitsOnce() {
        var transaction = BrowserSplitPanelWidthTransaction()
        transaction.resize(startingAt: 360, delta: -20)
        transaction.resize(startingAt: 360, delta: -70)
        XCTAssertEqual(transaction.width, 430)
        XCTAssertEqual(transaction.commit(), 430)
        XCTAssertNil(transaction.width)
        XCTAssertNil(transaction.commit())
        transaction.resize(startingAt: 430, delta: 1000)
        XCTAssertEqual(transaction.commit(), 280)
    }

    func testPanelAlwaysFollowsDropPlaceholderWithDistinctIdentity() {
        let tab = BrowserTab.startPage()
        let slots = BrowserSplitColumnSlot.slots(
            members: [tab], placeholderIndex: 1, includesPanel: true
        )
        XCTAssertEqual(slots.map(\.id), [.member(tab.id), .placeholder, .panel])
        XCTAssertNil(slots.last?.member)
    }

    func testPanelDividerExcludesCarryOnEitherSideOfTheRow() {
        let member = CGRect(x: 0, y: 0, width: 500, height: 600)
        let panel = CGRect(x: 500 + gap, y: 0, width: 360, height: 600)
        XCTAssertTrue(
            BrowserSplitCardLiftPolicy.isOverDivider(
                CGPoint(x: 500 + gap / 2, y: 100), orderedCardFrames: [member], panelFrame: panel
            ))
        XCTAssertTrue(
            BrowserSplitCardLiftPolicy.isOverDivider(
                CGPoint(x: 500 + gap / 2, y: 100), orderedCardFrames: [panel], panelFrame: member
            ))
        XCTAssertFalse(
            BrowserSplitCardLiftPolicy.isOverDivider(
                CGPoint(x: 200, y: 100), orderedCardFrames: [member], panelFrame: panel
            ))
    }
}
