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
        XCTAssertEqual(BrowserTabDragVisualPolicy.sourceScale(isDragging: true), 1.04)
        XCTAssertEqual(BrowserTabDragVisualPolicy.sourceOpacity(isDragging: true), 0.42)
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

    func testMobileInsertionSlotHasOneVisibleIndicatorOwner() {
        XCTAssertFalse(
            BrowserTabRowIndicatorOwnershipPolicy.showsAfterRowIndicator(
                hasVisibleFollowingRow: true
            )
        )
        XCTAssertTrue(
            BrowserTabRowIndicatorOwnershipPolicy.showsAfterRowIndicator(
                hasVisibleFollowingRow: false
            )
        )
        XCTAssertFalse(
            BrowserTabRowIndicatorOwnershipPolicy.showsSectionEndIndicator(
                hasVisibleRows: true
            )
        )
        XCTAssertTrue(
            BrowserTabRowIndicatorOwnershipPolicy.showsSectionEndIndicator(
                hasVisibleRows: false
            )
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

    func testMobileSourceStylingRequiresAReliableTerminalLifecycle() {
        XCTAssertFalse(
            BrowserTabDragVisualPolicy.usesPersistentSourceStyle(
                isDragging: true,
                hasReliableTerminalLifecycle: false
            )
        )
        XCTAssertTrue(
            BrowserTabDragVisualPolicy.usesPersistentSourceStyle(
                isDragging: true,
                hasReliableTerminalLifecycle: true
            )
        )
        XCTAssertFalse(
            BrowserTabDragVisualPolicy.usesPersistentSourceStyle(
                isDragging: false,
                hasReliableTerminalLifecycle: true
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

    @MainActor
    func testTransientDropExitDoesNotFlashTheIndicatorDuringTargetHandoff() async {
        let tabID = TabID()
        let dragState = BrowserTabDragState()
        let first = BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: TabID()
        )
        let second = BrowserTabDropLocation(
            placement: .current,
            folderID: nil,
            beforeTabID: nil
        )

        dragState.begin(
            item: BrowserTabDragItem(
                tabID: tabID,
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            placement: .current
        )
        _ = dragState.enter(first)
        dragState.deferLeave(first)
        _ = dragState.enter(second)
        try? await Task.sleep(for: BrowserTabDropStabilityPolicy.leaveDelay * 2)

        XCTAssertEqual(dragState.dropLocation, second)
        XCTAssertTrue(
            BrowserTabDropIndicatorPolicy.isVisible(
                at: second,
                dragState: dragState
            )
        )
        dragState.end()
    }

    @MainActor
    func testDeferredDropExitClearsAnAbandonedIndicator() async {
        let dragState = BrowserTabDragState()
        let location = BrowserTabDropLocation(
            placement: .saved,
            folderID: nil,
            beforeTabID: nil
        )

        dragState.begin(
            item: BrowserTabDragItem(
                tabID: TabID(),
                spaceID: SpaceID(),
                profileID: UUID()
            ),
            placement: .current
        )
        _ = dragState.enter(location)
        dragState.deferLeave(location)
        try? await Task.sleep(for: BrowserTabDropStabilityPolicy.leaveDelay * 2)

        XCTAssertNil(dragState.dropLocation)
        dragState.end()
    }

    /// The oldest morph in the app, pinned to exact numbers. Generalizing the
    /// preview to arbitrary shape pairs must not move any of them by a point.
    func testHeldTabPreviewInterpolatesFromRowToPinnedTile() {
        XCTAssertEqual(BrowserTabDragPreviewLayout.metrics(progress: 0).width, 220)
        XCTAssertEqual(BrowserTabDragPreviewLayout.metrics(progress: 0).height, 40)
        XCTAssertEqual(BrowserTabDragPreviewLayout.metrics(progress: 0).titleOpacity, 1)

        let quarter = BrowserTabDragPreviewLayout.metrics(progress: 0.25)
        XCTAssertEqual(quarter.width, 178)
        XCTAssertEqual(quarter.height, 43)
        XCTAssertEqual(quarter.titleOpacity, 0.75)

        let midpoint = BrowserTabDragPreviewLayout.metrics(progress: 0.5)
        XCTAssertEqual(midpoint.width, 136)
        XCTAssertEqual(midpoint.height, 46)
        XCTAssertEqual(midpoint.titleOpacity, 0.5)

        let threeQuarters = BrowserTabDragPreviewLayout.metrics(progress: 0.75)
        XCTAssertEqual(threeQuarters.width, 94)
        XCTAssertEqual(threeQuarters.height, 49)
        XCTAssertEqual(threeQuarters.titleOpacity, 0.25)

        XCTAssertEqual(BrowserTabDragPreviewLayout.metrics(progress: 1).width, 52)
        XCTAssertEqual(BrowserTabDragPreviewLayout.metrics(progress: 1).height, 52)
        XCTAssertEqual(BrowserTabDragPreviewLayout.metrics(progress: 1).titleOpacity, 0)

        XCTAssertEqual(
            BrowserTabDragPreviewLayout.metrics(
                progress: 0,
                rowWidth: 2_000
            ).width,
            BrowserTabDragPreviewLayout.maximumRowWidth
        )
    }

    /// The placement-shaped entry point is exactly the row-to-tile pair, so the
    /// generalization cannot have introduced a second answer for the same morph.
    func testThePlacementPreviewEntryIsTheRowToPinnedTilePair() {
        for step in 0...20 {
            let progress = CGFloat(step) / 20
            XCTAssertEqual(
                BrowserTabDragPreviewLayout.metrics(
                    progress: progress,
                    rowWidth: 260
                ),
                BrowserTabDragPreviewLayout.metrics(
                    from: .row,
                    to: .pinnedTile,
                    progress: progress,
                    rowWidth: 260
                )
            )
        }
    }

    /// The card the content area morphs a row into: page-sized, cornered like a
    /// page, and showing the title the tile hides.
    func testHeldTabPreviewInterpolatesFromRowToWebpageCard() {
        let resting = BrowserTabDragPreviewLayout.metrics(
            from: .row,
            to: .webpageCard,
            progress: 0
        )
        XCTAssertEqual(resting.width, 220)
        XCTAssertEqual(resting.height, 40)
        XCTAssertEqual(resting.cornerRadius, CrestRadius.control)
        XCTAssertEqual(resting.cardContentWeight, 0)

        let card = BrowserTabDragPreviewLayout.metrics(
            from: .row,
            to: .webpageCard,
            progress: 1
        )
        XCTAssertEqual(card.width, 240)
        XCTAssertEqual(card.height, 160)
        XCTAssertEqual(card.cornerRadius, BrowserChromeLayout.pageCornerRadius)
        XCTAssertEqual(card.titleOpacity, 1)
        XCTAssertEqual(card.cardContentWeight, 1)
        XCTAssertEqual(
            card.contentCentering,
            0,
            "The card draws its own centred content, so the row layout it "
                + "fades out of stays put."
        )
    }

    /// The pointer holds the same point of the preview whichever host draws it.
    ///
    /// The in-view lift offsets the preview from its row; the floating host has
    /// no row to offset from and places it against the pointer instead. Both have
    /// to put the grabbed point under the cursor or the preview would jump at the
    /// moment the hosts swap.
    func testAPointerAnchoredPreviewSitsWhereTheInRowPreviewWouldHave() {
        let rowOrigin = CGPoint(x: 12, y: 240)
        let grab = CGSize(width: 40, height: 18)
        let pointer = CGPoint(x: 700, y: 320)
        let rowWidth = BrowserTabDragPreviewLayout.rowSize.width

        for shape in [
            BrowserTabDragPreviewShape.row,
            .pinnedTile,
            .webpageCard,
        ] {
            let progress: CGFloat = shape == .row ? 0 : 1
            let metrics = BrowserTabDragPreviewLayout.metrics(
                from: .row,
                to: shape,
                progress: progress,
                rowWidth: rowWidth
            )
            let resting = BrowserTabDragPreviewLayout.metrics(
                from: .row,
                to: shape,
                progress: 0,
                rowWidth: rowWidth
            )
            let anchorX = BrowserTabDragPreviewLayout.anchorFraction(
                grabbed: grab.width / resting.width,
                progress: progress
            )
            let anchorY = BrowserTabDragPreviewLayout.anchorFraction(
                grabbed: grab.height / resting.height,
                progress: progress
            )
            // Where the in-row overlay lands: the row's own origin, moved by the
            // drag, plus the offset that modifier applies.
            let translation = CGSize(
                width: pointer.x - (rowOrigin.x + grab.width),
                height: pointer.y - (rowOrigin.y + grab.height)
            )
            let inRow = CGPoint(
                x: rowOrigin.x + translation.width + grab.width
                    - anchorX * metrics.width,
                y: rowOrigin.y + translation.height + grab.height
                    - anchorY * metrics.height
            )

            XCTAssertEqual(
                BrowserTabDragPreviewLayout.pointerAnchoredOrigin(
                    pointer: pointer,
                    grabOffset: grab,
                    targetShape: shape,
                    progress: progress,
                    rowWidth: rowWidth
                ),
                inRow,
                "\(shape) drifted between the two hosts."
            )
        }
    }

    /// A lift leaves the view tree the moment it is promoted and stays out of it
    /// until it ends. Handing the preview over at the page boundary only moves
    /// the seam: the view tree clips a travelling preview with window chrome and
    /// insets long before the page's web view gets to.
    func testALiftFloatsForTheWholeOfItsLiftWhereverThePointerGoes() {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let tabID = TabID()
        let state = BrowserSidebarReorderState()
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .splitContent(assignment),
                frame: CGRect(x: 260, y: 0, width: 900, height: 600)
            ),
            for: UUID()
        )
        state.register(
            splitCardFrame: CGRect(x: 260, y: 0, width: 900, height: 600),
            for: TabID(),
            owner: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(tabID),
                section: .tabs(placement: .current, folderID: nil),
                frame: CGRect(x: 0, y: 200, width: 240, height: 40)
            ),
            owner: UUID()
        )

        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: tabID,
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            ),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 40, y: 220)
        )
        // Still inside the sidebar, and already the host's to draw.
        let sidebarLift = state.floatingLift
        XCTAssertEqual(sidebarLift?.tabID, tabID)
        XCTAssertEqual(sidebarLift?.shape, .row)
        XCTAssertEqual(sidebarLift?.progress, 0)
        XCTAssertEqual(sidebarLift?.pointer, CGPoint(x: 40, y: 220))
        XCTAssertEqual(sidebarLift?.item.id, .tab(tabID))

        state.update(pointer: CGPoint(x: 700, y: 300))
        let floating = state.floatingLift
        XCTAssertEqual(floating?.tabID, tabID)
        XCTAssertEqual(floating?.shape, .webpageCard)
        XCTAssertEqual(floating?.progress, 1)
        XCTAssertEqual(floating?.pointer, CGPoint(x: 700, y: 300))
        XCTAssertEqual(floating?.grabOffset, CGSize(width: 40, height: 20))
        XCTAssertEqual(floating?.item.id, .tab(tabID))

        // A refused drop still has to be visible, so the host keeps it even with
        // nothing resolved — as the row it stayed.
        state.register(
            splitCardFrame: CGRect(x: 260, y: 0, width: 900, height: 600),
            for: tabID,
            owner: UUID()
        )
        state.update(pointer: CGPoint(x: 700, y: 300))
        XCTAssertNil(state.resolvedTarget)
        XCTAssertEqual(state.floatingLift?.shape, .row)
        XCTAssertEqual(state.floatingLift?.progress, 0)

        state.update(pointer: CGPoint(x: 40, y: 220))
        XCTAssertNotNil(
            state.floatingLift,
            "Coming back over the sidebar is not a reason to hand it back."
        )

        state.cancel()
        XCTAssertNil(state.floatingLift)
    }

    /// Folders and whole split groups are clipped by the same things a tab is,
    /// so their previews float too. What they do not do is change shape: a
    /// folder is a folder row and a group is a stack of member lines wherever
    /// they land, so both stay at the resting row the host draws them as.
    func testFoldersAndSplitGroupsFloatAsRows() {
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let contentFrame = CGRect(x: 260, y: 0, width: 900, height: 600)

        for item in [
            BrowserSidebarReorderItem.folder(
                BrowserFolderDragItem(
                    folderID: FolderID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID
                )
            ),
            .splitGroup(
                BrowserSplitGroupDragItem(
                    groupID: SplitGroupID(),
                    spaceID: assignment.spaceID,
                    profileID: assignment.profileID,
                    memberTabIDs: [TabID(), TabID()]
                )
            ),
        ] {
            let state = BrowserSidebarReorderState()
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .splitContent(assignment),
                    frame: contentFrame
                ),
                for: UUID()
            )
            state.begin(
                item: item,
                section: .tabs(placement: .current, folderID: nil),
                at: CGPoint(x: 40, y: 220)
            )
            state.update(pointer: CGPoint(x: 700, y: 300))

            let floating = state.floatingLift
            XCTAssertEqual(floating?.item, item, "\(item) was not floated.")
            XCTAssertEqual(floating?.shape, .row, "\(item) changed shape.")
            XCTAssertEqual(floating?.progress, 0)
            XCTAssertEqual(floating?.pointer, CGPoint(x: 700, y: 300))
            XCTAssertNil(
                floating?.tabID,
                "Neither is a tab, so neither names one for the preview."
            )
            XCTAssertNil(
                state.resolvedTarget,
                "The content area still refuses both: floating is presentation, "
                    + "not acceptance."
            )

            state.cancel()
            XCTAssertNil(state.floatingLift)
        }
    }

    // MARK: - In-view sidebar reorder geometry

    private func reorderRow(
        _ id: BrowserSidebarReorderItemID,
        section: BrowserSidebarReorderSection,
        _ frame: CGRect
    ) -> BrowserSidebarReorderRow {
        BrowserSidebarReorderRow(id: id, section: section, frame: frame)
    }

    /// A list insertion lands wherever the pointer has passed a row's midpoint.
    func testListInsertionIndexTracksRowMidpoints() {
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let ids = (0..<3).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let rows = ids.enumerated().map { index, id in
            reorderRow(
                id,
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
        let section = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let ids = (0..<3).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        let rows = ids.enumerated().map { index, id in
            reorderRow(
                id,
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

    /// Rows keep their layout slots during a drag, so displacement is the delta
    /// between the slot a row occupies and the slot it should occupy.
    func testDisplacementOpensAGapAndClosesTheVacatedSlot() {
        let layout = BrowserSidebarReorderPolicy.SlotLayout.list(stride: 40)

        // Lifting slot 0 and dropping at the end pulls the follower back one slot.
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.displacement(
                candidateIndex: 0,
                draggedSlot: 0,
                insertionIndex: 2,
                layout: layout
            ),
            CGSize(width: 0, height: -40)
        )
        // A row at or after the gap steps forward to open it.
        XCTAssertEqual(
            BrowserSidebarReorderPolicy.displacement(
                candidateIndex: 1,
                draggedSlot: 2,
                insertionIndex: 0,
                layout: layout
            ),
            CGSize(width: 0, height: 40)
        )
    }

    // MARK: - Cross-section reorder feedback

    /// Every direction a lift can cross in, read the same way: the section the
    /// pointer is over resolves the insertion, the rows there open the gap, and
    /// the row at the seam draws the line. Crossing into a section is not a
    /// weaker case of reordering inside one — a drop the target section cannot
    /// show is a drop with nothing to aim at.
    func testEveryCrossSectionDropShowsTheSectionWhereItWillLand() {
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
        let down = CGSize(width: 0, height: 40)
        let listLine = BrowserSidebarReorderIndicator(
            side: .before,
            flowsHorizontally: false
        )
        let gridLine = BrowserSidebarReorderIndicator(
            side: .before,
            flowsHorizontally: true
        )

        // Current into the saved list, short of the second row's midpoint.
        var outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: current,
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 100, y: 150),
            watching: sidebar.saved
        )
        XCTAssertEqual(
            outcome.kind,
            .insert(section: saved, beforeID: sidebar.saved[1], index: 1)
        )
        XCTAssertEqual(outcome.displacements, [.zero, down, down])
        XCTAssertEqual(outcome.indicators, [nil, listLine, nil])

        // Saved back into the current list.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 100, y: 290),
            watching: sidebar.current
        )
        XCTAssertEqual(
            outcome.kind,
            .insert(section: current, beforeID: sidebar.current[1], index: 1)
        )
        XCTAssertEqual(outcome.displacements, [.zero, down])
        XCTAssertEqual(outcome.indicators, [nil, listLine])

        // Current into the pinned grid: the cell it displaces wraps a line.
        outcome = sidebar.crossing(
            lift: sidebar.current[0],
            from: current,
            at: CGPoint(x: 100, y: 270),
            to: CGPoint(x: 50, y: 20),
            watching: sidebar.pinned
        )
        XCTAssertEqual(
            outcome.kind,
            .insert(section: pinned, beforeID: sidebar.pinned[1], index: 1)
        )
        XCTAssertEqual(
            outcome.displacements,
            [.zero, CGSize(width: -100, height: 40)]
        )
        XCTAssertEqual(outcome.indicators, [nil, gridLine])

        // Pinned into the saved list.
        outcome = sidebar.crossing(
            lift: sidebar.pinned[0],
            from: pinned,
            at: CGPoint(x: 40, y: 20),
            to: CGPoint(x: 100, y: 190),
            watching: sidebar.saved
        )
        XCTAssertEqual(
            outcome.kind,
            .insert(section: saved, beforeID: sidebar.saved[2], index: 2)
        )
        XCTAssertEqual(outcome.displacements, [.zero, .zero, down])
        XCTAssertEqual(outcome.indicators, [nil, nil, listLine])

        // Saved past the last pinned cell: nothing moves, and the last cell
        // draws the line on its own trailing edge instead.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 150, y: 20),
            watching: sidebar.pinned
        )
        XCTAssertEqual(
            outcome.kind,
            .insert(section: pinned, beforeID: nil, index: 2)
        )
        XCTAssertEqual(outcome.displacements, [.zero, .zero])
        XCTAssertEqual(
            outcome.indicators,
            [
                nil,
                BrowserSidebarReorderIndicator(
                    side: .after,
                    flowsHorizontally: true
                ),
            ]
        )

        // The control: reordering inside one section still closes the slot the
        // lifted row vacated as well as opening the one it is heading for.
        outcome = sidebar.crossing(
            lift: sidebar.saved[0],
            from: saved,
            at: CGPoint(x: 100, y: 110),
            to: CGPoint(x: 100, y: 190),
            watching: Array(sidebar.saved.dropFirst())
        )
        XCTAssertEqual(
            outcome.kind,
            .insert(section: saved, beforeID: sidebar.saved[2], index: 1)
        )
        XCTAssertEqual(
            outcome.displacements,
            [CGSize(width: 0, height: -40), .zero]
        )
        XCTAssertEqual(outcome.indicators, [nil, listLine])
    }

    /// A folder's tabs are their own section, measured inside the saved list
    /// that holds the folder. A tab arriving from the current list has to open
    /// the gap among the folder's rows, not in the list behind them.
    func testALiftCrossingIntoAFolderScopedSectionDisplacesItsRows() {
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
                section: .tabs(placement: .saved, folderID: nil),
                CGRect(x: 0, y: 190, width: 200, height: 40)
            ),
            owner: UUID()
        )
        state.register(
            row: reorderRow(
                lifted,
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
        XCTAssertEqual(state.displacement(for: filed[0]), .zero)
        XCTAssertEqual(
            state.displacement(for: filed[1]),
            CGSize(width: 0, height: 40)
        )
        XCTAssertEqual(
            state.indicator(for: filed[1]),
            BrowserSidebarReorderIndicator(
                side: .before,
                flowsHorizontally: false
            )
        )
        XCTAssertEqual(
            state.displacement(for: unfiled),
            .zero,
            "The list behind the folder is not the section being dropped into."
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
            to: CGPoint(x: 100, y: 150),
            watching: sidebar.saved
        )

        XCTAssertEqual(
            outcome.kind,
            .insert(
                section: .tabs(placement: .saved, folderID: nil),
                beforeID: sidebar.saved[1],
                index: 1
            )
        )
        XCTAssertEqual(
            outcome.displacements,
            [.zero, CGSize(width: 0, height: 40), CGSize(width: 0, height: 40)]
        )
        XCTAssertEqual(
            outcome.indicators,
            [
                nil,
                BrowserSidebarReorderIndicator(
                    side: .before,
                    flowsHorizontally: false
                ),
                nil,
            ]
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

        private let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )

        init() {
            register(pinned, in: .tabs(placement: .pinned, folderID: nil)) {
                CGRect(x: CGFloat($0) * 100, y: 0, width: 90, height: 40)
            }
            register(saved, in: .tabs(placement: .saved, folderID: nil)) {
                CGRect(x: 0, y: 100 + CGFloat($0) * 40, width: 200, height: 40)
            }
            register(current, in: .tabs(placement: .current, folderID: nil)) {
                CGRect(x: 0, y: 260 + CGFloat($0) * 40, width: 200, height: 40)
            }
            register(
                .tabs(placement: .pinned, folderID: nil),
                over: CGRect(x: 0, y: 0, width: 200, height: 50)
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

        /// One crossing: lift `id` out of `section`, hold the pointer at
        /// `pointer`, and report what resolved and what each watched row was
        /// told to do.
        func crossing(
            lift id: BrowserSidebarReorderItemID,
            from section: BrowserSidebarReorderSection,
            at liftPoint: CGPoint,
            to pointer: CGPoint,
            watching rows: [BrowserSidebarReorderItemID]
        ) -> (
            kind: BrowserSidebarReorderTarget.Kind?,
            displacements: [CGSize],
            indicators: [BrowserSidebarReorderIndicator?]
        ) {
            state.begin(item: item(id), section: section, at: liftPoint)
            state.update(pointer: pointer)
            defer { state.cancel() }
            return (
                state.resolvedTarget?.kind,
                rows.map { state.displacement(for: $0) },
                rows.map { state.indicator(for: $0) }
            )
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
    func testAFolderHoldingEverySavedTabOpensAGapForACurrentLift() {
        for unfiledBand in [CGFloat.zero, CrestSpacing.medium] {
            let sidebar = FolderHeldSavedSidebar(unfiledBand: unfiledBand)

            let outcome = sidebar.crossing(
                lift: sidebar.current[0],
                from: .tabs(placement: .current, folderID: nil),
                at: CGPoint(x: 100, y: 265),
                to: CGPoint(x: 100, y: 160),
                watching: sidebar.filed
            )

            XCTAssertEqual(
                outcome.kind,
                .insert(
                    section: .tabs(
                        placement: .saved,
                        folderID: sidebar.folderID
                    ),
                    beforeID: sidebar.filed[1],
                    index: 1
                )
            )
            XCTAssertEqual(
                outcome.displacements,
                [.zero, CGSize(width: 0, height: 40)]
            )
            XCTAssertEqual(
                outcome.indicators,
                [
                    nil,
                    BrowserSidebarReorderIndicator(
                        side: .before,
                        flowsHorizontally: false
                    ),
                ]
            )
        }
    }

    /// The insertion line is drawn by the row beside the gap, so a section with
    /// no rows of its own had nothing to draw it: the unfiled saved run under a
    /// folder that holds everything went completely dark for an arriving lift
    /// while still accepting the drop. An empty section draws the line itself.
    func testTheEmptyUnfiledSavedRunDrawsItsOwnInsertionLine() {
        let sidebar = FolderHeldSavedSidebar(unfiledBand: CrestSpacing.medium)
        let unfiled = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )

        sidebar.state.begin(
            item: sidebar.item(sidebar.current[0]),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 265)
        )
        // The band below the folder group: inside the saved list, outside the
        // folder that fills the rest of it.
        sidebar.state.update(pointer: CGPoint(x: 100, y: 221))
        defer { sidebar.state.cancel() }

        XCTAssertEqual(
            sidebar.state.resolvedTarget?.kind,
            .insert(section: unfiled, beforeID: nil, index: 0)
        )
        XCTAssertEqual(
            sidebar.state.emptySectionIndicator(for: unfiled),
            BrowserSidebarReorderIndicator(
                side: .before,
                flowsHorizontally: false
            )
        )
        XCTAssertNil(
            sidebar.state.emptySectionIndicator(
                for: .tabs(placement: .saved, folderID: sidebar.folderID)
            ),
            "A section with rows still lets them draw the line."
        )
        for row in sidebar.filed {
            XCTAssertEqual(sidebar.state.displacement(for: row), .zero)
            XCTAssertNil(sidebar.state.indicator(for: row))
        }
    }

    /// The same darkness reaches an untouched pinned grid and a cleared current
    /// list, so the affordance is the section's rather than the saved list's.
    /// A grid inserts between columns, so its line stands on end.
    func testEveryEmptySectionDrawsTheLineItsRowsWouldHave() {
        let state = BrowserSidebarReorderState()
        let assignment = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let pinned = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let current = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let saved = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        let lifted = BrowserSidebarReorderItemID.tab(TabID())
        state.register(
            row: reorderRow(
                lifted,
                section: saved,
                CGRect(x: 0, y: 100, width: 200, height: 40)
            ),
            owner: UUID()
        )
        for (section, frame) in [
            (pinned, CGRect(x: 0, y: 0, width: 200, height: 50)),
            (saved, CGRect(x: 0, y: 95, width: 200, height: 50)),
            (current, CGRect(x: 0, y: 200, width: 200, height: 60)),
        ] {
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: frame
                ),
                for: UUID()
            )
        }
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: lifted.tabID ?? TabID(),
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            )
        )

        state.begin(item: item, section: saved, at: CGPoint(x: 100, y: 120))
        defer { state.cancel() }

        state.update(pointer: CGPoint(x: 100, y: 25))
        XCTAssertEqual(
            state.emptySectionIndicator(for: pinned),
            BrowserSidebarReorderIndicator(
                side: .before,
                flowsHorizontally: true
            )
        )
        XCTAssertNil(state.emptySectionIndicator(for: current))

        state.update(pointer: CGPoint(x: 100, y: 230))
        XCTAssertEqual(
            state.emptySectionIndicator(for: current),
            BrowserSidebarReorderIndicator(
                side: .before,
                flowsHorizontally: false
            )
        )
        XCTAssertNil(state.emptySectionIndicator(for: pinned))

        // The section the lifted row came from is empty once that row is taken
        // out of it, so it too has to show where the row would go back.
        state.update(pointer: CGPoint(x: 100, y: 120))
        XCTAssertEqual(
            state.emptySectionIndicator(for: saved),
            BrowserSidebarReorderIndicator(
                side: .before,
                flowsHorizontally: false
            )
        )
    }

    /// Nothing resolved, nothing drawn: an empty section is not a permanent
    /// invitation, only the answer to a drag that is genuinely over it.
    func testAnEmptySectionShowsNothingWithoutAResolvedTarget() {
        let state = BrowserSidebarReorderState()
        let saved = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )

        XCTAssertNil(state.emptySectionIndicator(for: saved))

        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: TabID(),
                    spaceID: SpaceID(),
                    profileID: UUID()
                )
            ),
            section: .tabs(placement: .current, folderID: nil),
            at: CGPoint(x: 100, y: 265)
        )
        XCTAssertNil(
            state.emptySectionIndicator(for: saved),
            "No zone is registered, so nothing resolved."
        )
        state.cancel()
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
            to pointer: CGPoint,
            watching rows: [BrowserSidebarReorderItemID]
        ) -> (
            kind: BrowserSidebarReorderTarget.Kind?,
            displacements: [CGSize],
            indicators: [BrowserSidebarReorderIndicator?]
        ) {
            state.begin(item: item(id), section: section, at: liftPoint)
            state.update(pointer: pointer)
            defer { state.cancel() }
            return (
                state.resolvedTarget?.kind,
                rows.map { state.displacement(for: $0) },
                rows.map { state.indicator(for: $0) }
            )
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

    /// A grid reflows in two axes, so a cell wrapping to the next line moves back
    /// across the columns as well as down.
    func testGridDisplacementWrapsAcrossColumns() {
        let displacement = BrowserSidebarReorderPolicy.displacement(
            candidateIndex: 2,
            draggedSlot: 3,
            insertionIndex: 0,
            layout: .grid(columns: 3, columnStride: 100, rowStride: 50)
        )
        XCTAssertEqual(displacement, CGSize(width: -200, height: 50))
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

    /// A lifted group keeps its row shape wherever it lands, so nothing morphs.
    func testALiftedSplitGroupNeverTakesAMorphTargetPlacement() {
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

        state.begin(item: item, section: section, at: CGPoint(x: 10, y: 10))

        XCTAssertTrue(state.isDragging)
        XCTAssertNil(state.liftTargetShape)
        state.cancel()

        // A tab lifted from the same section does report a shape to morph
        // toward, so the nil above is the group's own rule rather than an
        // unresolved target.
        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: TabID(),
                    spaceID: SpaceID(),
                    profileID: UUID()
                )
            ),
            section: section,
            at: CGPoint(x: 10, y: 10)
        )
        XCTAssertEqual(state.liftTargetShape, .row)
        state.cancel()
    }

    /// A lift with nowhere resolved holds the shape it started as, so a pinned
    /// tab dragged into open space still reads as a tile.
    func testAPinnedLiftHoldsItsTileShapeUntilAListResolves() {
        let state = BrowserSidebarReorderState()
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: TabID(),
                spaceID: SpaceID(),
                profileID: UUID()
            )
        )

        state.begin(
            item: item,
            section: .tabs(placement: .pinned, folderID: nil),
            at: CGPoint(x: 10, y: 10)
        )
        XCTAssertEqual(state.liftTargetShape, .pinnedTile)
        state.cancel()
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

    func testPinnedTabAccentPrefersSiteThemeThenExtractedColorThenWhite() {
        let theme = BrowserTabIconAccent(red: 0.1, green: 0.2, blue: 0.3)
        let extracted = BrowserTabIconAccent(red: 0.7, green: 0.4, blue: 0.2)

        XCTAssertEqual(
            BrowserTabIconAccentResolver.resolve(
                siteTheme: theme,
                extracted: extracted
            ),
            theme
        )
        XCTAssertEqual(
            BrowserTabIconAccentResolver.resolve(
                siteTheme: nil,
                extracted: extracted
            ),
            extracted
        )
        XCTAssertEqual(
            BrowserTabIconAccentResolver.resolve(
                siteTheme: nil,
                extracted: nil
            ),
            .white
        )
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
