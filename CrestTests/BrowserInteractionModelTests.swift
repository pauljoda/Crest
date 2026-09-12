import AppKit
import XCTest

import struct SwiftUI.Color

@testable import Crest

@MainActor
final class BrowserInteractionModelTests: XCTestCase {
    func testTabActivationSelectsTheModelBeforePresentingItsPage() {
        let tabID = TabID()
        var events: [String] = []

        BrowserTabActivationPolicy.activate(
            tabID,
            selectTab: { selectedID in
                XCTAssertEqual(selectedID, tabID)
                events.append("select")
            },
            presentPage: {
                events.append("present")
            }
        )

        XCTAssertEqual(events, ["select", "present"])
    }

    func testSpaceIdentityAndOrderingRemainStableAcrossEdits() throws {
        var session = BrowserSession.preview
        let profilesBySpaceID = Dictionary(
            uniqueKeysWithValues: session.spaces.map {
                ($0.id, $0.profile.id)
            }
        )
        session.addSpace()
        let movedID = try XCTUnwrap(session.spaces.first?.id)

        session.moveSpaces(
            from: IndexSet(integer: session.spaces.startIndex),
            to: session.spaces.endIndex
        )
        session.updateSpaceIdentity(
            movedID,
            name: "  Research  ",
            symbol: "graduationcap.fill",
            accent: .teal
        )

        let moved = try XCTUnwrap(session.spaces.last)
        XCTAssertEqual(moved.id, movedID)
        XCTAssertEqual(moved.name, "Research")
        XCTAssertEqual(moved.symbol, "graduationcap.fill")
        XCTAssertEqual(moved.accent, .teal)
        for (spaceID, profileID) in profilesBySpaceID {
            XCTAssertEqual(session.space(id: spaceID)?.profile.id, profileID)
        }
        XCTAssertEqual(session.selectedSpaceID, session.spaces.dropLast().last?.id)
    }

    func testDragStateMorphsAsTheTabCrossesPlacementZones() throws {
        let tabID = TabID()
        let spaceID = SpaceID()
        let item = BrowserTabDragItem(
            tabID: tabID,
            spaceID: spaceID,
            profileID: UUID()
        )
        let dragState = BrowserTabDragState()

        dragState.begin(item: item, placement: .current)
        XCTAssertTrue(dragState.isDragging(item))

        XCTAssertEqual(dragState.currentPlacement, .current)

        let pinned = BrowserTabDropLocation(
            placement: .pinned,
            folderID: nil,
            beforeTabID: nil
        )
        XCTAssertTrue(dragState.enter(pinned))
        XCTAssertEqual(dragState.currentPlacement, .pinned)
        XCTAssertEqual(dragState.liveMoveCount, 0)
        dragState.recordLiveMove()
        XCTAssertEqual(dragState.liveMoveCount, 1)
        XCTAssertFalse(dragState.enter(pinned))

        dragState.leave(pinned, restoringSourcePlacement: true)
        XCTAssertEqual(dragState.currentPlacement, .current)
        XCTAssertNil(dragState.dropLocation)

        let pinnedCell = BrowserTabDropLocation(
            placement: .pinned,
            folderID: nil,
            beforeTabID: TabID()
        )
        XCTAssertTrue(dragState.enter(pinnedCell))
        dragState.leavePinnedZone()
        XCTAssertEqual(dragState.currentPlacement, .current)
        XCTAssertNil(dragState.dropLocation)

        XCTAssertTrue(dragState.enter(pinned))
        XCTAssertEqual(dragState.currentPlacement, .pinned)

        let folderID = FolderID()
        let saved = BrowserTabDropLocation(
            placement: .saved,
            folderID: folderID,
            beforeTabID: nil
        )
        XCTAssertTrue(dragState.enter(saved))
        XCTAssertEqual(dragState.currentPlacement, .saved)
        XCTAssertEqual(dragState.dropLocation?.folderID, folderID)

        dragState.end()
        XCTAssertFalse(dragState.isDragging(item))
        XCTAssertNil(dragState.item)
        XCTAssertNil(dragState.currentPlacement)
        XCTAssertNil(dragState.dropLocation)
    }

    func testRowInsertionLocationTracksTheFingerAcrossTheRowsMidpoint() {
        let before = BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: TabID()
        )
        let after = BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: TabID()
        )

        XCTAssertEqual(
            BrowserTabRowInsertionPolicy.location(
                y: 10,
                rowHeight: 44,
                before: before,
                after: after
            ),
            before
        )
        XCTAssertEqual(
            BrowserTabRowInsertionPolicy.location(
                y: 22,
                rowHeight: 44,
                before: before,
                after: after
            ),
            after
        )
        XCTAssertEqual(
            BrowserTabRowInsertionPolicy.location(
                y: 42,
                rowHeight: 44,
                before: before,
                after: after
            ),
            after
        )
    }

    func testRowInsertionLowerHalfResolvesBeforeTheActualFollowingTab() {
        let first = BrowserTab(title: "First", url: nil, placement: .current)
        let second = BrowserTab(title: "Second", url: nil, placement: .current)
        let third = BrowserTab(title: "Third", url: nil, placement: .current)
        let tabs = [first, second, third]

        XCTAssertEqual(
            BrowserTabRowInsertionPolicy.followingTabID(
                after: first.id,
                in: tabs
            ),
            second.id
        )
        XCTAssertEqual(
            BrowserTabRowInsertionPolicy.followingTabID(
                after: second.id,
                in: tabs
            ),
            third.id
        )
        XCTAssertNil(
            BrowserTabRowInsertionPolicy.followingTabID(
                after: third.id,
                in: tabs
            )
        )

        XCTAssertEqual(
            BrowserTabRowInsertionPolicy.followingTabIDs(in: tabs),
            [first.id: second.id, second.id: third.id]
        )
    }

    func testMobileDragLifecycleUsesTheNativeCompletionOnlyWhereItExists() {
        XCTAssertFalse(
            BrowserTabDragSessionLifecyclePolicy.usesNativeCompletion(
                runtimeMajorVersion: 26
            )
        )
        XCTAssertTrue(
            BrowserTabDragSessionLifecyclePolicy.usesNativeCompletion(
                runtimeMajorVersion: 27
            )
        )
        XCTAssertFalse(
            BrowserTabDragSessionLifecyclePolicy.shouldEnd(for: .active)
        )
        XCTAssertTrue(
            BrowserTabDragSessionLifecyclePolicy.shouldEnd(for: .ended)
        )
        XCTAssertTrue(
            BrowserTabDragSessionLifecyclePolicy.shouldEnd(
                for: .dataTransferCompleted
            )
        )
    }

    func testFallbackTouchReleaseClearsAHeldTabAfterDropResolution() async {
        let tabID = TabID()
        let dragState = BrowserTabDragState()
        let item = BrowserTabDragItem(
            tabID: tabID,
            spaceID: SpaceID(),
            profileID: UUID()
        )

        dragState.begin(item: item, placement: .current)
        dragState.endAfterTouchRelease()

        XCTAssertTrue(dragState.isDragging(item))
        try? await Task.sleep(
            for: BrowserDragReleaseFallbackPolicy.cleanupDelay * 2
        )
        XCTAssertFalse(dragState.isDragging(item))
        XCTAssertNil(dragState.dropLocation)
    }

    func testFallbackTouchReleaseClearsAHeldFolderAfterDropResolution() async {
        let folderID = FolderID()
        let dragState = BrowserFolderDragState()
        let item = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: SpaceID(),
            profileID: UUID()
        )

        dragState.begin(item: item)
        dragState.endAfterTouchRelease()

        XCTAssertTrue(dragState.isDragging(item))
        try? await Task.sleep(
            for: BrowserDragReleaseFallbackPolicy.cleanupDelay * 2
        )
        XCTAssertFalse(dragState.isDragging(item))
        XCTAssertNil(dragState.dropLocation)
    }

    func testOpeningATabContextMenuCancelsItsFalseDragLift() {
        let tabID = TabID()
        let dragState = BrowserTabDragState()
        let firstItem = BrowserTabDragItem(
            tabID: tabID,
            spaceID: SpaceID(),
            profileID: UUID()
        )

        dragState.begin(item: firstItem, placement: .current)
        dragState.contextMenuDidOpen(for: firstItem.runtimeAssignment)
        let secondItem = BrowserTabDragItem(
            tabID: tabID,
            spaceID: SpaceID(),
            profileID: UUID()
        )
        dragState.begin(item: secondItem, placement: .current)
        dragState.contextMenuDidClose(for: secondItem.runtimeAssignment)

        XCTAssertFalse(dragState.isDragging(secondItem))
        XCTAssertNil(dragState.dropLocation)
    }

    func testOpeningAFolderContextMenuCancelsItsFalseDragLift() {
        let folderID = FolderID()
        let dragState = BrowserFolderDragState()
        let firstItem = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: SpaceID(),
            profileID: UUID()
        )

        dragState.begin(item: firstItem)
        dragState.contextMenuDidOpen(for: firstItem)
        let secondItem = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: SpaceID(),
            profileID: UUID()
        )
        dragState.begin(item: secondItem)
        dragState.contextMenuDidClose(for: secondItem)

        XCTAssertFalse(dragState.isDragging(secondItem))
        XCTAssertNil(dragState.dropLocation)
    }

    // MARK: - In-view sidebar reorder geometry

    private func reorderRow(
        _ id: BrowserSidebarReorderItemID,
        in space: BrowserSpaceRuntimeAssignment,
        section: BrowserSidebarReorderSection,
        _ frame: CGRect
    ) -> BrowserSidebarReorderRow {
        BrowserSidebarReorderRow(
            id: id,
            space: space,
            section: section,
            frame: frame
        )
    }

    /// A list insertion lands wherever the pointer has passed a row's midpoint.
    func testListInsertionIndexTracksRowMidpoints() {
        let space = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let ids = (0..<3).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let rows = ids.enumerated().map { index, id in
            reorderRow(
                id,
                in: space,
                section: section,
                CGRect(x: 0, y: CGFloat(index) * 40, width: 200, height: 40)
            )
        }

        // Above the first midpoint (y=20) nothing has been passed.
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.insertionIndex(
                at: CGPoint(x: 100, y: 5),
                orderedRows: rows,
                excluding: nil
            ),
            0
        )
        // Past the last midpoint (y=100) the drop appends.
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.insertionIndex(
                at: CGPoint(x: 100, y: 300),
                orderedRows: rows,
                excluding: nil
            ),
            3
        )
        XCTAssertNil(
            BrowserSidebarReorderPolicy.insertionAnchor(
                index: 3,
                orderedRows: rows,
                excluding: nil
            )
        )
    }

    /// The grid compares horizontally only on a cell's own line. Comparing both
    /// axes at once made every cell on the line count as passed, which made
    /// leftward moves impossible.
    func testGridInsertionAllowsMovingLeftWithinALine() {
        let space = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let section = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let ids = (0..<3).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let rows = ids.enumerated().map { index, id in
            reorderRow(
                id,
                in: space,
                section: section,
                CGRect(x: CGFloat(index) * 100, y: 0, width: 90, height: 40)
            )
        }

        // Left of the first cell's center, even while below the line's middle.
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.insertionIndex(
                at: CGPoint(x: 10, y: 30),
                orderedRows: rows,
                excluding: nil
            ),
            0
        )
        // Between the first and second centers.
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.insertionIndex(
                at: CGPoint(x: 120, y: 20),
                orderedRows: rows,
                excluding: nil
            ),
            1
        )
    }

    // MARK: - Cross-section reorder feedback

    /// Cross-section drops retain the exact destination section and insertion index.
    func testCrossSectionDropsResolveTheDestinationSectionAndIndex() {
        let sidebar = StackedSidebar()
        let pinned = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let saved = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        let current = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )

        // Current into the saved list, short of the second row's midpoint.
        var outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: current,
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 100, y: 150)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: saved, beforeID: sidebar.saved[1], index: 1)
        )

        // Saved back into the current list.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 100, y: 290)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: current, beforeID: sidebar.current[1], index: 1)
        )

        // Current into Pinned: two columns become three; the drop uses the
        // final grid width rather than shifting a fixed grid off its edge.
        outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: current,
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 50, y: 20)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: pinned, beforeID: sidebar.pinned[1], index: 1)
        )

        // Pinned into the saved list.
        outcome = sidebar.crossing(
            lift: sidebar.pinned[0],
            from: pinned,
            at: CGPoint(x: 40, y: 20),
            to: CGPoint(x: 100, y: 190)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: saved, beforeID: sidebar.saved[2], index: 2)
        )

        // Saved past the last pinned cell resolves to the end of that section.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 190, y: 20)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: pinned, beforeID: nil, index: 2)
        )

        // Reordering within one section resolves after excluding the lifted row.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 100, y: 190)
        )
        XCTAssertEqual(
            outcome,
            .insert(section: saved, beforeID: sidebar.saved[2], index: 1)
        )

    }

    /// A folder's tabs are their own section, measured inside the saved list
    /// that holds the folder. A tab arriving from the current list has to open
    /// the gap among the folder's rows, not in the list behind them.
    func testALiftCrossingIntoAFolderScopedSectionResolvesItsRows() {
        let state = BrowserSidebarReorderState()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let folderID = FolderID()
        let folderSection = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: folderID
        )
        let filed = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let unfiled = BrowserSidebarReorderItemID.tab(TabID())
        let lifted = BrowserSidebarReorderItemID.tab(TabID())

        for (index, id) in filed.enumerated() {
            state.register(
                row: reorderRow(
                    id,
                    in: assignment,
                    section: folderSection,
                    CGRect(
                        x: 0,
                        y: 100 + CGFloat(index) * 40,
                        width: 200,
                        height: 40
                    )
                ),
                owner: UUID()
            )
        }
        state.register(
            row: reorderRow(
                unfiled,
                in: assignment,
                section: .tabs(placement: .saved, folderID: nil),
                CGRect(x: 0, y: 190, width: 200, height: 40)
            ),
            owner: UUID()
        )
        state.register(
            row: reorderRow(
                lifted,
                in: assignment,
                section: .tabs(placement: .current, folderID: nil),
                CGRect(x: 0, y: 260, width: 200, height: 40)
            ),
            owner: UUID()
        )
        // The folder group's own run sits inside the saved list's zone.
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(.tabs(placement: .saved, folderID: nil)),
                frame: CGRect(x: 0, y: 95, width: 200, height: 140)
            ),
            for: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(folderSection),
                frame: CGRect(x: 0, y: 95, width: 200, height: 90)
            ),
            for: UUID()
        )

        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: lifted.tabID ?? TabID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            ),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 270)
        )
        state.update(pointer: CGPoint(x: 100, y: 150))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: folderSection, beforeID: filed[1], index: 1)
        )

        state.cancel()
    }

    /// A row that changes section is an arriving view in the section it lands in
    /// and a departing view in the one it left, and SwiftUI runs the departing
    /// view's `onDisappear` after the arriving one has measured itself. Keyed by
    /// item alone, that late removal wipes the registration the arrival just
    /// made: the row drops out of its new section's geometry, nothing displaces
    /// around it, and every later drop aims straight past it.
    func testARowMovingBetweenSectionsKeepsTheRegistrationItsArrivalMade() {
        let sidebar = StackedSidebar()

        // The saved list's middle row got there by being dragged out of the
        // current list: its new row measured itself, then its old row left.
        let arrival = UUID()
        let departure = UUID()
        sidebar.state.register(
            row: reorderRow(
                sidebar.saved[1],
                in: sidebar.assignment,
                section: .tabs(placement: .saved, folderID: nil),
                CGRect(x: 0, y: 140, width: 200, height: 40)
            ),
            owner: arrival
        )
        sidebar.state.removeRow(sidebar.saved[1], owner: departure)

        let outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 100, y: 150)
        )

        XCTAssertEqual(
            outcome,
            .insert(
                section: .tabs(placement: .saved, folderID: nil),
                beforeID: sidebar.saved[1],
                index: 1
            )
        )

    }

    /// The three macOS sidebar sections at fixed geometry: a two-cell pinned
    /// grid on top, a three-row saved list under it, and a two-row current list
    /// at the bottom, each wrapped in the zone its section registers.
    @MainActor
    private struct StackedSidebar {
        let state = BrowserSidebarReorderState()
        let pinned = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let saved = (0..<3).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let current = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }

        /// The Space every row here belongs to. Readable from outside because a
        /// row registration has to say which Space's run it stands in.
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )

        init() {
            register(pinned, in: .tabs(placement: .pinned, folderID: nil)) {
                CGRect(x: CGFloat($0) * 104, y: 0, width: 96, height: 47)
            }
            register(saved, in: .tabs(placement: .saved, folderID: nil)) {
                CGRect(x: 0, y: 100 + CGFloat($0) * 40, width: 200, height: 40)
            }
            register(current, in: .tabs(placement: .current, folderID: nil)) {
                CGRect(x: 0, y: 260 + CGFloat($0) * 40, width: 200, height: 40)
            }
            register(
                .tabs(placement: .pinned, folderID: nil),
                over: CGRect(x: 0, y: 0, width: 200, height: 47)
            )
            register(
                .tabs(placement: .saved, folderID: nil),
                over: CGRect(x: 0, y: 95, width: 200, height: 130)
            )
            // The saved list registers a folder run over the same frame.
            register(
                .folders(parentID: nil),
                over: CGRect(x: 0, y: 95, width: 200, height: 130)
            )
            register(
                .tabs(placement: .current, folderID: nil),
                over: CGRect(x: 0, y: 255, width: 200, height: 90)
            )
        }

        /// Resolve a destination while the pointer is held, then end the lift.
        func crossing(
            lift id: BrowserSidebarReorderItemID,
            from section: BrowserSidebarReorderSection,
            at liftPoint: CGPoint,
            to pointer: CGPoint
        ) -> BrowserSidebarReorderTarget.Kind? {
            state.begin(item: item(id), section: section, at: liftPoint)
            state.update(pointer: pointer)
            defer { state.cancel() }
            return state.resolvedTarget?.kind
        }

        func item(
            _ id: BrowserSidebarReorderItemID
        ) -> BrowserSidebarReorderItem {
            .tab(
                BrowserTabDragItem(
                    tabID: id.tabID ?? TabID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            )
        }

        private func register(
            _ ids: [BrowserSidebarReorderItemID],
            in section: BrowserSidebarReorderSection,
            frame: (Int) -> CGRect
        ) {
            for (index, id) in ids.enumerated() {
                state.register(
                    row: BrowserSidebarReorderRow(
                        id: id,
                        space: assignment,
                        section: section,
                        frame: frame(index)
                    ),
                    owner: UUID()
                )
            }
        }

        private func register(
            _ section: BrowserSidebarReorderSection,
            over frame: CGRect
        ) {
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: frame
                ),
                for: UUID()
            )
        }
    }

    // MARK: - A folder that fills the saved list

    /// The saved list wraps its folder groups, so a Space whose every saved tab
    /// lives in one folder measures the folder group and the list around it as
    /// the same rectangle: a `VStack(spacing: 0)` holding a single child is that
    /// child. Ranking overlapping sections by area alone leaves that a tie, and
    /// a tie is settled by whichever registration the registry happens to yield
    /// first — so the list can outrank the folder nested inside it. Nesting is
    /// structural, not a matter of pixels, so it is ranked before area.
    func testAFolderFillingTheSavedListOutranksTheListAroundIt() {
        let frame = CGRect(x: 0, y: 95, width: 200, height: 120)
        let folderID = FolderID()
        let folderRun = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: folderID
        )
        let savedList = BrowserSidebarReorderZone(
            target: .section(.tabs(placement: .saved, folderID: nil)),
            frame: frame
        )
        let folderGroup = BrowserSidebarReorderZone(
            target: .section(folderRun),
            frame: frame
        )
        let tab = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: TabID(),
                spaceID: SpaceID(),
                profileID: UUID()
            )
        )

        // Over the folder's rows, and past the bottom of both, where the slop
        // fallback answers instead of containment.
        for point in [CGPoint(x: 100, y: 160), CGPoint(x: 100, y: 260)] {
            for zones in [[savedList, folderGroup], [folderGroup, savedList]] {
                XCTAssertEqual(
                    BrowserSidebarReorderPolicy.zone(
                        at: point,
                        in: zones,
                        accepting: tab
                    )?
                    .target,
                    .section(folderRun),
                    "The nested folder run owns the rows it measures."
                )
            }
        }
    }

    /// The live shape behind the report: pinned tiles on top, one folder holding
    /// every saved tab, no unfiled saved rows at all, and a current list below.
    /// A tab lifted out of the current list and held over the folder's rows has
    /// to open the gap among them.
    ///
    /// Run with and without the band the unfiled run keeps below the folder.
    /// Without it the saved list measures exactly what the folder group
    /// measures, which is the shape the report came from.
    func testAFolderHoldingEverySavedTabResolvesACurrentLift() {
        for unfiledBand in [CGFloat.zero, CrestSpacing.medium] {
            let sidebar = FolderHeldSavedSidebar(unfiledBand: unfiledBand)

            let outcome = sidebar.crossing(
                lift: sidebar.current[0],
                from: .tabs(placement: .current, folderID: nil),
                at: CGPoint(x: 100, y: 265),
                to: CGPoint(x: 100, y: 160)
            )

            XCTAssertEqual(
                outcome,
                .insert(
                    section: .tabs(
                        placement: .saved,
                        folderID: sidebar.folderID
                    ),
                    beforeID: sidebar.filed[1],
                    index: 1
                )
            )

        }
    }

    /// The live macOS shape behind the report: a two-cell pinned grid, a saved
    /// list whose only content is one folder group holding every saved tab, and
    /// a current list below. The saved list and the folder group measure the
    /// same rectangle, because the list is a `VStack(spacing: 0)` around that
    /// single group.
    @MainActor
    private struct FolderHeldSavedSidebar {
        let state = BrowserSidebarReorderState()
        let folderID = FolderID()
        let filed = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let current = (0..<2).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }

        /// Header row plus the two filed rows under it.
        private static let folderGroup = CGRect(
            x: 0,
            y: 95,
            width: 200,
            height: 120
        )
        /// The folder group plus whatever band the unfiled run keeps below it.
        /// At zero the saved list *is* the folder group, which is what the live
        /// sidebar measured when the report came in.
        private let savedList: CGRect

        private let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )

        init(unfiledBand: CGFloat = 0) {
            savedList = CGRect(
                x: Self.folderGroup.minX,
                y: Self.folderGroup.minY,
                width: Self.folderGroup.width,
                height: Self.folderGroup.height + unfiledBand
            )
            for (index, id) in filed.enumerated() {
                register(
                    id,
                    in: .tabs(placement: .saved, folderID: folderID),
                    at: CGRect(
                        x: 16,
                        y: 135 + CGFloat(index) * 40,
                        width: 184,
                        height: 40
                    )
                )
            }
            for (index, id) in current.enumerated() {
                register(
                    id,
                    in: .tabs(placement: .current, folderID: nil),
                    at: CGRect(
                        x: 0,
                        y: 255 + CGFloat(index) * 40,
                        width: 200,
                        height: 40
                    )
                )
            }
            // The saved list registers its own run and the folder run beside it,
            // and the folder group registers both of its runs over itself.
            register(.tabs(placement: .saved, folderID: nil), over: savedList)
            register(.folders(parentID: nil), over: savedList)
            register(
                .tabs(placement: .saved, folderID: folderID),
                over: Self.folderGroup
            )
            register(
                .folders(parentID: folderID),
                over: Self.folderGroup.divided(
                    atDistance: 40,
                    from: .minYEdge
                ).remainder
            )
            register(
                .tabs(placement: .current, folderID: nil),
                over: CGRect(x: 0, y: 245, width: 200, height: 90)
            )
        }

        func crossing(
            lift id: BrowserSidebarReorderItemID,
            from section: BrowserSidebarReorderSection,
            at liftPoint: CGPoint,
            to pointer: CGPoint
        ) -> BrowserSidebarReorderTarget.Kind? {
            state.begin(item: item(id), section: section, at: liftPoint)
            state.update(pointer: pointer)
            defer { state.cancel() }
            return state.resolvedTarget?.kind
        }

        func item(
            _ id: BrowserSidebarReorderItemID
        ) -> BrowserSidebarReorderItem {
            .tab(
                BrowserTabDragItem(
                    tabID: id.tabID ?? TabID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            )
        }

        private func register(
            _ id: BrowserSidebarReorderItemID,
            in section: BrowserSidebarReorderSection,
            at frame: CGRect
        ) {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: id,
                    space: assignment,
                    section: section,
                    frame: frame
                ),
                owner: UUID()
            )
        }

        private func register(
            _ section: BrowserSidebarReorderSection,
            over frame: CGRect
        ) {
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: frame
                ),
                for: UUID()
            )
        }
    }

    /// Tabs and folders each reorder only among their own kind, so overlapping
    /// sections in a folder group cannot capture the wrong item.
    func testSectionsOnlyAcceptTheirOwnKindOfItem() {
        let tab = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(tabID: TabID(), spaceID: SpaceID(), profileID: UUID())
        )
        let folder = BrowserSidebarReorderItem.folder(
            BrowserFolderDragItem(
                folderID: FolderID(),
                spaceID: SpaceID(),
                profileID: UUID()
            )
        )

        XCTAssertTrue(
            BrowserSidebarReorderPolicy.accepts(
                item: tab,
                in: .tabs(placement: .saved, folderID: nil)
            )
        )
        XCTAssertFalse(
            BrowserSidebarReorderPolicy.accepts(
                item: tab,
                in: .folders(parentID: nil)
            )
        )
        XCTAssertTrue(
            BrowserSidebarReorderPolicy.accepts(
                item: folder,
                in: .folders(parentID: nil)
            )
        )
        XCTAssertFalse(
            BrowserSidebarReorderPolicy.accepts(
                item: folder,
                in: .tabs(placement: .pinned, folderID: nil)
            )
        )
    }

    /// A split group is a run of tabs, so it reorders among tabs — but never into
    /// the pinned grid, because pinned tabs cannot be members.
    func testSplitGroupsAreAcceptedOnlyByNonPinnedTabSections() {
        let group = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: SplitGroupID(),
                spaceID: SpaceID(),
                profileID: UUID(),
                memberTabIDs: [TabID(), TabID()]
            )
        )

        XCTAssertTrue(
            BrowserSidebarReorderPolicy.accepts(
                item: group,
                in: .tabs(placement: .current, folderID: nil)
            )
        )
        XCTAssertTrue(
            BrowserSidebarReorderPolicy.accepts(
                item: group,
                in: .tabs(placement: .saved, folderID: FolderID())
            )
        )
        XCTAssertFalse(
            BrowserSidebarReorderPolicy.accepts(
                item: group,
                in: .tabs(placement: .pinned, folderID: nil)
            )
        )
        XCTAssertFalse(
            BrowserSidebarReorderPolicy.accepts(
                item: group,
                in: .folders(parentID: nil)
            )
        )
    }

    /// Folder-nesting and Space zones outrank the sections behind them. A group
    /// cannot land in either, so it must fall through to the section instead of
    /// resolving a target its commit would refuse.
    func testSplitGroupDragsFallThroughFolderAndSpaceZonesToTheSection() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        let point = CGPoint(x: 100, y: 20)
        let section = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let zones = [
            BrowserSidebarReorderZone(target: .section(section), frame: frame),
            BrowserSidebarReorderZone(target: .folder(FolderID()), frame: frame),
            BrowserSidebarReorderZone(target: .space(assignment), frame: frame),
        ]
        let group = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: SplitGroupID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID,
                memberTabIDs: [TabID(), TabID()]
            )
        )
        let tab = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: TabID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            )
        )

        XCTAssertEqual(
            BrowserSidebarReorderPolicy.zone(
                at: point,
                in: zones,
                accepting: group
            )?
            .target,
            .section(section)
        )
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.zone(
                at: point,
                in: zones,
                accepting: tab
            )?
            .target,
            .space(assignment),
            "A tab still takes the most specific zone."
        )
    }

    /// iOS stages a group lift from `.onDrag`, which runs at the press. Nothing
    /// may be lifted until the drop delegate reports a position: a press
    /// released without pulling produces no session, and a stage that lifted
    /// eagerly would hide the row with nothing in flight to put it back.
    func testAStagedSplitGroupLiftIsInertUntilADropPositionArrives() {
        let state = BrowserSidebarReorderState()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let groupID = SplitGroupID()
        let item = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: groupID,
                spaceID: SpaceID(),
                profileID: UUID(),
                memberTabIDs: [TabID(), TabID()]
            )
        )
        state.register(
            row: reorderRow(
                item.id,
                in: item.spaceAssignment,
                section: section,
                CGRect(x: 8, y: 110, width: 374, height: 120)
            ),
            owner: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(section),
                frame: CGRect(x: 0, y: 100, width: 390, height: 300)
            ),
            for: UUID()
        )

        state.stage(item: item, section: section)
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.isLifted(.splitGroup(groupID)))
        XCTAssertFalse(state.suppressesActivation)

        // The first tracked position is the proof a drag is genuinely in
        // flight, and it promotes the stage without any extra call site.
        state.update(pointer: CGPoint(x: 195, y: 150))
        XCTAssertTrue(state.isDragging)
        XCTAssertTrue(state.isLifted(.splitGroup(groupID)))
        state.cancel()
    }

    /// A staged lift whose session ends away from the sidebar is cleared by the
    /// mobile session modifier. Nothing may resurrect it afterwards, or the row
    /// stays invisible and untappable until the app is relaunched.
    func testACancelledSplitGroupStageCannotBePromotedLater() {
        let state = BrowserSidebarReorderState()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let item = BrowserSidebarReorderItem.splitGroup(
            BrowserSplitGroupDragItem(
                groupID: SplitGroupID(),
                spaceID: SpaceID(),
                profileID: UUID(),
                memberTabIDs: [TabID(), TabID()]
            )
        )

        state.stage(item: item, section: section)
        state.cancel()

        state.update(pointer: CGPoint(x: 195, y: 150))
        XCTAssertFalse(state.isDragging)
        XCTAssertNil(state.end())
    }

    /// Only the middle of a collapsed folder nests; the edges stay available for
    /// reordering past it.
    func testNestingClaimsOnlyTheMiddleOfAFolderRow() {
        let frame = CGRect(x: 0, y: 100, width: 200, height: 40)
        let nesting = BrowserSidebarReorderPolicy.nestingFrame(for: frame)

        XCTAssertEqual(nesting.height, 20)
        XCTAssertFalse(nesting.contains(CGPoint(x: 100, y: 105)))
        XCTAssertTrue(nesting.contains(CGPoint(x: 100, y: 120)))
        XCTAssertFalse(nesting.contains(CGPoint(x: 100, y: 135)))
    }

    func testFolderDragUsesSavedInsertionLocationsAndCannotEnterPinnedTabs() {
        let folderID = FolderID()
        let siblingID = FolderID()
        let spaceID = SpaceID()
        let dragState = BrowserFolderDragState()
        let item = BrowserFolderDragItem(
            folderID: folderID,
            spaceID: spaceID,
            profileID: UUID()
        )
        let location = BrowserFolderDropLocation(
            parentID: nil,
            beforeSiblingID: siblingID
        )

        dragState.begin(item: item)
        XCTAssertTrue(dragState.isDragging(item))
        XCTAssertTrue(dragState.enter(location))
        XCTAssertEqual(dragState.dropLocation, location)

        dragState.end()
        XCTAssertNil(dragState.item)
        XCTAssertNil(dragState.dropLocation)
    }

    func testDraggingIntoAnotherSpacesSectionReownsTheTabAndContinuesTheLiveDrag() throws {
        let browser = BrowserStore.preview()
        let source = try XCTUnwrap(browser.session.spaces.first)
        let destination = try XCTUnwrap(browser.session.spaces.last)
        let tab = try XCTUnwrap(source.currentTabs.first)
        let item = BrowserTabDragItem(
            tabID: tab.id,
            spaceID: source.id,
            profileID: source.profile.id
        )
        browser.tabDragState.begin(item: item, placement: tab.placement)

        browser.selectSpace(destination.id)
        XCTAssertTrue(
            browser.moveTab(
                item,
                to: .saved,
                matching: BrowserSpaceRuntimeAssignment(space: destination)
            )
        )

        XCTAssertFalse(try XCTUnwrap(browser.session.space(id: source.id)).contains(tab.id))
        let moved = try XCTUnwrap(
            browser.session.space(id: destination.id)?.tabs.first(where: { $0.id == tab.id })
        )
        XCTAssertEqual(moved.placement, .saved)
        XCTAssertEqual(browser.session.selectedTab?.id, tab.id)
        XCTAssertEqual(browser.tabDragState.item?.spaceID, destination.id)
        XCTAssertEqual(browser.tabDragState.currentPlacement, .current)
    }

    func testNewTabAndLocationUseDistinctCommandPaletteModes() {
        let chrome = BrowserChromeState()

        chrome.presentCommandPalette()
        XCTAssertTrue(chrome.isCommandPalettePresented)
        XCTAssertEqual(chrome.commandPaletteMode, .newTab)
        XCTAssertEqual(chrome.commandPaletteMode?.initialQuery, "")

        chrome.openLocation("https://webkit.org/blog/")
        XCTAssertTrue(chrome.isCommandPalettePresented)
        XCTAssertEqual(
            chrome.commandPaletteMode,
            .editLocation("https://webkit.org/blog/")
        )
        XCTAssertEqual(
            chrome.commandPaletteMode?.initialQuery,
            "https://webkit.org/blog/"
        )
    }

    func testNewTabFocusesAnAlreadySelectedStartPageWithoutAnOverlay() {
        let chrome = BrowserChromeState()
        let initialFocusRequest = chrome.startPageFocusRequest

        chrome.openNewTab(isStartPageSelected: true)

        XCTAssertNil(chrome.commandPaletteMode)
        XCTAssertNotEqual(chrome.startPageFocusRequest, initialFocusRequest)

        let focusedRequest = chrome.startPageFocusRequest
        chrome.openNewTab(isStartPageSelected: false)

        XCTAssertEqual(chrome.commandPaletteMode, .newTab)
        XCTAssertEqual(chrome.startPageFocusRequest, focusedRequest)
    }

    func testRootNewTabActionKeepsTheSelectedStartPageCohesive() throws {
        let browser = BrowserStore.preview()
        let pages = BrowserPagePool()
        let chrome = BrowserChromeState()
        let model = BrowserRootModel(
            browser: browser,
            pages: pages,
            chrome: chrome,
            spaceAccess: BrowserSpaceAccessController(),
            windowState: nil,
            startupBehavior: .showStartPage,
            persistedSidebarWidth: BrowserChromeLayout.sidebarIdealWidth
        )
        let selectedSpaceID = try XCTUnwrap(browser.selectedSpace?.id)
        let selectedTabID = try XCTUnwrap(browser.selectedTab?.id)
        let currentTabs = try XCTUnwrap(browser.selectedSpace?.currentTabs.map(\.id))
        let initialFocusRequest = chrome.startPageFocusRequest

        model.openNewTab()
        model.openNewTab()

        XCTAssertEqual(browser.selectedSpace?.id, selectedSpaceID)
        XCTAssertEqual(browser.selectedTab?.id, selectedTabID)
        XCTAssertEqual(browser.selectedSpace?.currentTabs.map(\.id), currentTabs)
        XCTAssertNil(chrome.commandPaletteMode)
        XCTAssertEqual(chrome.startPageFocusRequest, initialFocusRequest + 2)
    }

    func testStartPageHasADistinctIdentityFromTheNewTabAction() {
        let tab = BrowserTab.startPage()

        XCTAssertEqual(tab.title, "Start Page")
        XCTAssertEqual(tab.symbol, BrowserTab.startPageSymbol)
        XCTAssertTrue(tab.isStartPage)
        XCTAssertNil(tab.url)
    }

    func testMiddleClickClosesOnlyCurrentTabsAndUnloadsSavedTabs() {
        XCTAssertEqual(BrowserTabMiddleClickPolicy.action(for: .current), .close)
        XCTAssertEqual(BrowserTabMiddleClickPolicy.action(for: .pinned), .unload)
        XCTAssertEqual(BrowserTabMiddleClickPolicy.action(for: .saved), .unload)
    }
}
