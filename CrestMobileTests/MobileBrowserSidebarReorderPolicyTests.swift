import CoreGraphics
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserSidebarReorderPolicyTests: XCTestCase {
    /// The compact shell's lift is staged by `.onDrag` and promoted by the first
    /// position the drop delegate reports — the three-piece contract iOS needs
    /// because `UIContextMenuInteraction` cancels any gesture that competes with
    /// it, so drag-and-drop is the only arbiter that can arm a lift on a row
    /// that also carries a menu.
    ///
    /// A stage that never promotes is the exact shape of a row that cannot be
    /// picked up: the provider runs, the row wiggles, and nothing lifts. Nothing
    /// covered the promote step before this.
    func testStagedLiftIsInertUntilTheFirstReportedPositionPromotesIt() {
        let fixture = ReorderStagingFixture()

        fixture.state.stage(item: fixture.item, section: fixture.section)

        XCTAssertFalse(
            fixture.state.isDragging,
            "Staging runs at the press, before any drag exists. Lifting there "
                + "hides a row while nothing is in flight."
        )
        XCTAssertFalse(fixture.state.isLifted(fixture.item.id))
        XCTAssertNil(fixture.state.resolvedTarget)

        fixture.state.update(pointer: fixture.pointerOverNeighbour)

        XCTAssertTrue(
            fixture.state.isLifted(fixture.item.id),
            "The first position the drop delegate reports is the proof the "
                + "system drag is genuinely in flight, and must promote the "
                + "staged lift."
        )
        XCTAssertEqual(fixture.state.lift?.item, fixture.item)
        XCTAssertEqual(fixture.state.lift?.section, fixture.section)
        XCTAssertEqual(
            fixture.state.lift?.rowSize,
            fixture.draggedFrame.size,
            "Promotion must adopt the frame the row registered, or the gap it "
                + "leaves behind has no size."
        )
        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            fixture.section,
            "A promoted lift resolves a target from the same sample."
        )
    }

    /// The commit path only exists on the far side of promotion: a drop that
    /// lands while the lift is still staged has no item and no target to move.
    func testPromotedLiftIsWhatMakesADropCommittable() {
        let fixture = ReorderStagingFixture()

        fixture.state.stage(item: fixture.item, section: fixture.section)
        XCTAssertNil(
            fixture.state.end(),
            "A stage that never saw a position has nothing to commit."
        )

        fixture.state.stage(item: fixture.item, section: fixture.section)
        fixture.state.update(pointer: fixture.pointerOverNeighbour)

        let drop = fixture.state.end()
        XCTAssertEqual(drop?.item, fixture.item)
        XCTAssertEqual(drop?.target.section, fixture.section)
        XCTAssertFalse(
            fixture.state.isDragging,
            "Ending the drop clears the lift."
        )
    }

    /// A drag session that ends without ever reaching the sidebar is cleared by
    /// `BrowserMobileReorderSessionModifier`. The stage has to go with it, or a
    /// later unrelated sample would resurrect a lift nobody asked for.
    func testCancelClearsTheStageSoALaterSampleCannotResurrectIt() {
        let fixture = ReorderStagingFixture()

        fixture.state.stage(item: fixture.item, section: fixture.section)
        fixture.state.cancel()
        fixture.state.update(pointer: fixture.pointerOverNeighbour)

        XCTAssertFalse(
            fixture.state.isDragging,
            "A cancelled session leaves no stage behind to promote."
        )
        XCTAssertNil(fixture.state.resolvedTarget)
    }

    /// The compact shell puts the sidebar on screen three ways, and only one of
    /// them pushes a page with the system's navigation zoom. None of the three
    /// grows a surface out of a row through matched geometry, so the anchor a row
    /// claims must come out the same for every placement.
    ///
    /// This is the regression: while the answer flipped with the placement, the
    /// two placements without the native zoom handed every row a partnerless
    /// matched-geometry anchor — a presentation transform over the very view
    /// `.onDrag` lifts — and rows there could not be picked up at all, while the
    /// tab viewer kept lifting. The reorder machinery was never involved.
    func testNoCompactPlacementAnchorsARowWithMatchedGeometry() {
        for usesNativeNavigationTransition in [true, false] {
            let capabilities = BrowserInteractionCapabilities(
                supportsHover: true,
                supportsTouch: true,
                showsRowDropIndicators: true,
                reservesReorderSectionZones: true,
                usesNativeNavigationTransition: usesNativeNavigationTransition,
                pairsRowWithPromotedSurface: false
            )

            XCTAssertFalse(
                BrowserSidebarInteractionPolicy
                    .usesMatchedGeometryPromotionDestination(capabilities),
                "native zoom: \(usesNativeNavigationTransition)"
            )
        }
    }

    /// Everything one staged lift needs: a measured row to lift, a neighbour to
    /// aim at, and the section zone that answers for both.
    @MainActor
    private struct ReorderStagingFixture {
        let state: BrowserSidebarReorderState
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let item: BrowserSidebarReorderItem
        let draggedFrame = CGRect(x: 8, y: 110, width: 374, height: 44)
        let neighbourFrame = CGRect(x: 8, y: 154, width: 374, height: 44)

        var pointerOverNeighbour: CGPoint {
            CGPoint(x: neighbourFrame.midX, y: neighbourFrame.midY)
        }

        init() {
            state = BrowserSidebarReorderState()
            let spaceID = SpaceID()
            let profileID = UUID()
            item = .tab(
                BrowserTabDragItem(
                    tabID: TabID(),
                    spaceID: spaceID,
                    profileID: profileID
                )
            )
            state.register(
                row: BrowserSidebarReorderRow(
                    id: item.id,
                    space: item.spaceAssignment,
                    section: section,
                    frame: draggedFrame
                ),
                owner: UUID()
            )
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(TabID()),
                    space: item.spaceAssignment,
                    section: section,
                    frame: neighbourFrame
                ),
                owner: UUID()
            )
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: draggedFrame.union(neighbourFrame)
                        .insetBy(dx: -8, dy: -10)
                ),
                for: UUID()
            )
        }
    }

    func testSplitGroupLiftClosesItsWholeMixedHeightSlot() {
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let groupID = SplitGroupID()
        let space = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let rows = [
            BrowserSidebarReorderRow(
                id: .tab(TabID()),
                space: space,
                section: section,
                frame: CGRect(x: 8, y: 110, width: 374, height: 44)
            ),
            BrowserSidebarReorderRow(
                id: .splitGroup(groupID),
                space: space,
                section: section,
                frame: CGRect(x: 8, y: 154, width: 374, height: 120)
            ),
            BrowserSidebarReorderRow(
                id: .tab(TabID()),
                space: space,
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
                space: item.spaceAssignment,
                section: source,
                frame: groupFrame
            ),
            owner: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(TabID()),
                space: item.spaceAssignment,
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
