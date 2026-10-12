import Foundation
import XCTest

@testable import CrestMobile

@MainActor
final class MobileSplitCardPagerTests: XCTestCase {
    func testAdjacentMemberStepsOneCardInEachDirection() {
        let members = memberIDs(count: 3)

        XCTAssertEqual(
            MobileSplitCardPager.adjacentMember(
                of: members[0],
                in: members,
                direction: .next
            ),
            members[1]
        )
        XCTAssertEqual(
            MobileSplitCardPager.adjacentMember(
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
            MobileSplitCardPager.adjacentMember(
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
            MobileSplitCardPager.adjacentMember(
                of: members[2],
                in: members,
                direction: .next
            )
        )
    }

    func testAdjacentMemberIgnoresATabThatIsNoLongerAMember() {
        let members = memberIDs(count: 2)
        let closedMember = fixedUUID(0xDE)

        XCTAssertNil(
            MobileSplitCardPager.adjacentMember(
                of: closedMember,
                in: members,
                direction: .next
            ),
            "A member closed mid-swipe has no neighbour to page to."
        )
    }

    // MARK: - Helpers

    private func memberIDs(count: Int) -> [UUID] {
        (0..<count).map { fixedUUID($0 + 1) }
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }
}
