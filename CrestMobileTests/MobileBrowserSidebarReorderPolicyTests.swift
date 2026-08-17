import CoreGraphics
import XCTest

@testable import CrestMobile

@MainActor
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

    /// A cross-section move offsets the destination rows, but offset is only a
    /// presentation transform. The destination list must also grow by the full
    /// measured height of an incoming split group so the next section cannot
    /// paint into its two-row preview. The same contract applies in both
    /// directions across the Saved/Open boundary.
    func testCrossSectionSplitGroupReservesItsFullHeightInEitherDestination() {
        assertCrossSectionSplitGroupReservation(
            source: .tabs(placement: .current, folderID: nil),
            destination: .tabs(placement: .saved, folderID: nil),
            sourceY: 230,
            destinationY: 110
        )
        assertCrossSectionSplitGroupReservation(
            source: .tabs(placement: .saved, folderID: nil),
            destination: .tabs(placement: .current, folderID: nil),
            sourceY: 110,
            destinationY: 270
        )
    }

    private func assertCrossSectionSplitGroupReservation(
        source: BrowserSidebarReorderSection,
        destination: BrowserSidebarReorderSection,
        sourceY: CGFloat,
        destinationY: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let state = BrowserSidebarReorderState()
        let groupID = SplitGroupID()
        let groupFrame = CGRect(x: 8, y: sourceY, width: 374, height: 120)
        let destinationFrame = CGRect(
            x: 8,
            y: destinationY,
            width: 374,
            height: 44
        )
        let item = BrowserSplitGroupDragItem(
            groupID: groupID,
            spaceID: SpaceID(),
            profileID: UUID(),
            memberTabIDs: [TabID(), TabID()]
        )

        state.register(
            row: BrowserSidebarReorderRow(
                id: .splitGroup(groupID),
                section: source,
                frame: groupFrame
            ),
            owner: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(TabID()),
                section: destination,
                frame: destinationFrame
            ),
            owner: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(source),
                frame: groupFrame.insetBy(dx: -8, dy: -10)
            ),
            for: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(destination),
                frame: destinationFrame.insetBy(dx: -8, dy: -10)
            ),
            for: UUID()
        )

        state.begin(
            item: .splitGroup(item),
            section: source,
            at: CGPoint(x: groupFrame.midX, y: groupFrame.midY)
        )
        state.update(
            pointer: CGPoint(
                x: destinationFrame.midX,
                y: destinationFrame.midY
            )
        )

        XCTAssertEqual(
            state.resolvedTarget?.section,
            destination,
            file: file,
            line: line
        )
        XCTAssertEqual(
            state.incomingLiftReservationHeight(for: destination),
            groupFrame.height,
            "The destination must reserve the split preview's complete height.",
            file: file,
            line: line
        )
        XCTAssertEqual(
            state.incomingLiftReservationHeight(for: source),
            0,
            "The source already owns the lifted row's vacant layout slot.",
            file: file,
            line: line
        )

        state.cancel()
        XCTAssertEqual(
            state.incomingLiftReservationHeight(for: destination),
            0,
            "The temporary section capacity must disappear with the drag.",
            file: file,
            line: line
        )
    }
}
