import CoreGraphics
import XCTest

@testable import CrestMobile

final class MobileBrowserSidebarReorderPolicyTests: XCTestCase {
    func testSplitGroupLiftClosesItsWholeMixedHeightSlot() {
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let groupID = SplitGroupID()
        let rows = [
            BrowserSidebarReorderRow(
                id: .tab(TabID()),
                section: section,
                frame: CGRect(x: 8, y: 110, width: 374, height: 44)
            ),
            BrowserSidebarReorderRow(
                id: .splitGroup(groupID),
                section: section,
                frame: CGRect(x: 8, y: 154, width: 374, height: 120)
            ),
            BrowserSidebarReorderRow(
                id: .tab(TabID()),
                section: section,
                frame: CGRect(x: 8, y: 274, width: 374, height: 44)
            ),
        ]

        let displacement = BrowserSidebarReorderPolicy.displacement(
            candidateIndex: 1,
            draggedSlot: 1,
            insertionIndex: 2,
            layout: BrowserSidebarReorderPolicy.slotLayout(
                for: rows,
                fallbackStride: rows[1].frame.height
            )
        )

        XCTAssertEqual(
            displacement,
            CGSize(width: 0, height: -120),
            "The plain tab must close the complete tall slot the group vacated."
        )
    }
}
