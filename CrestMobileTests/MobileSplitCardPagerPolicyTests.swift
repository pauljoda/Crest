import XCTest

@testable import CrestMobile

@MainActor
final class MobileSplitCardPagerPolicyTests: XCTestCase {
    func testDirectDragStaysDisabledSoTheCarouselNeverFightsWebContentPans() {
        XCTAssertFalse(
            MobileSplitCardPagerPolicy.allowsDirectDrag,
            """
            A horizontal ScrollView over live WKWebViews competes with every \
            page's own horizontal pan. Paging is programmatic for 0.4.
            """
        )
        XCTAssertFalse(MobileSplitCardPagerPolicy.showsScrollIndicators)
    }

    func testPagerAppearsOnlyForARunLongEnoughToRender() {
        XCTAssertFalse(MobileSplitCardPagerPolicy.isPagerPresented(memberCount: 0))
        XCTAssertFalse(
            MobileSplitCardPagerPolicy.isPagerPresented(memberCount: 1),
            "A run of one is a plain tab and takes the single-page path."
        )
        XCTAssertTrue(MobileSplitCardPagerPolicy.isPagerPresented(memberCount: 2))
        XCTAssertTrue(
            MobileSplitCardPagerPolicy.isPagerPresented(
                memberCount: BrowserSplitGroupPolicy.maximumMembers
            )
        )
    }

    func testAdjacentMemberStepsOneCardInEachDirection() {
        let members = memberIDs(count: 3)

        XCTAssertEqual(
            MobileSplitCardPagerPolicy.adjacentMember(
                of: members[0],
                in: members,
                direction: .next
            ),
            members[1]
        )
        XCTAssertEqual(
            MobileSplitCardPagerPolicy.adjacentMember(
                of: members[2],
                in: members,
                direction: .previous
            ),
            members[1]
        )
    }

    func testAdjacentMemberClampsAtBothEndsInsteadOfWrapping() {
        let members = memberIDs(count: 3)

        XCTAssertNil(
            MobileSplitCardPagerPolicy.adjacentMember(
                of: members[0],
                in: members,
                direction: .previous
            ),
            """
            A swipe is spatial: running off the leading end and reappearing at \
            the trailing one would read as the carousel losing its place.
            """
        )
        XCTAssertNil(
            MobileSplitCardPagerPolicy.adjacentMember(
                of: members[2],
                in: members,
                direction: .next
            )
        )
    }

    func testAdjacentMemberIgnoresATabThatIsNoLongerAMember() {
        let members = memberIDs(count: 2)
        let closedMember = TabID(rawValue: fixedUUID(0xDE))

        XCTAssertNil(
            MobileSplitCardPagerPolicy.adjacentMember(
                of: closedMember,
                in: members,
                direction: .next
            ),
            "A member closed mid-swipe has no neighbour to page to."
        )
    }

    // MARK: - Helpers

    private func memberIDs(count: Int) -> [TabID] {
        (0..<count).map { TabID(rawValue: fixedUUID($0 + 1)) }
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}
