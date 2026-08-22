import CoreGraphics
import Foundation
import XCTest

@testable import CrestMobile

private func padTab(id: TabID, title: String) -> BrowserTab {
    BrowserTab(
        id: id,
        title: title,
        url: URL(string: "https://\(id.rawValue.uuidString).crest.test"),
        placement: .current,
        lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func padUUID(_ finalByte: UInt8) -> UUID {
    UUID(
        uuid: (
            0x50, 0x41, 0x44, 0x53, 0x50, 0x4C, 0x49, 0x54,
            0x44, 0x52, 0x4F, 0x50, 0x00, 0x00, 0x00, finalByte
        )
    )
}

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

    /// The Space strip has to hold still for the whole of a touch lift, and a
    /// touch lift is the one kind neither drag state ever hears about.
    ///
    /// `BrowserSpacePager` locked on `tabDragState`/`folderDragState`, which the
    /// compact `.onDrag` path never populates — it stages straight into the
    /// reorder state. So the pager stayed scrollable under every finger drag,
    /// and carrying a row to the edge paged to another Space mid-lift: a move no
    /// lifted tab can make, and one that swaps the rows its drop was aimed at.
    ///
    /// Staging has to count, not just promotion. The stretch between the two is
    /// exactly when the finger is still travelling toward the edge.
    func testTheSpaceStripLocksFromTheMomentALiftIsStaged() {
        let fixture = ReorderStagingFixture()

        XCTAssertFalse(fixture.state.hasLiftInFlight)
        XCTAssertFalse(lockedPager(fixture.state))

        fixture.state.stage(item: fixture.item, section: fixture.section)
        XCTAssertTrue(
            lockedPager(fixture.state),
            "A staged lift must already own the horizontal axis."
        )

        fixture.state.update(pointer: fixture.pointerOverNeighbour)
        XCTAssertTrue(lockedPager(fixture.state), "And still while it moves.")

        _ = fixture.state.end()
        XCTAssertFalse(
            lockedPager(fixture.state),
            "The strip pages again once the drop has landed."
        )
    }

    /// A stage nothing ever came back for must not lock the strip for good.
    ///
    /// The stage is cleared by the promotion that lifts it, the drop that ends
    /// it, or a context menu taking the press. On a runtime without
    /// `onDragSessionUpdated` — the deployment target is iOS 26.1, and
    /// `BrowserMobileReorderSessionModifier` compiles away to its content below
    /// iOS 27 — a press that produces neither a session nor a menu is cleared by
    /// nothing at all. `hasLiftInFlight` then stayed true for the life of the
    /// process, and the Space pager reads exactly that: horizontal paging died
    /// in every sidebar on screen at once, in the floating sidebar and the
    /// full-screen tab viewer alike, with no lifted row to explain it.
    func testAStageNoDragClaimsStopsLockingTheSpaceStrip() async throws {
        let fixture = ReorderStagingFixture(
            stagedLiftExpiration: .milliseconds(10)
        )

        fixture.state.stage(item: fixture.item, section: fixture.section)
        XCTAssertTrue(lockedPager(fixture.state))

        try await Task.sleep(for: .milliseconds(60))

        XCTAssertFalse(
            fixture.state.hasLiftInFlight,
            "An unpromoted stage is written off rather than held for good."
        )
        XCTAssertFalse(
            lockedPager(fixture.state),
            "And the strip pages again once it is."
        )
        XCTAssertFalse(
            fixture.state.suppressesActivation,
            "No drag ever happened, so the row stays openable."
        )
    }

    /// The backstop must never collect a stage that a drag did claim.
    func testAPromotedLiftOutlivesTheStageExpiry() async throws {
        let fixture = ReorderStagingFixture(
            stagedLiftExpiration: .milliseconds(10)
        )

        fixture.state.stage(item: fixture.item, section: fixture.section)
        fixture.state.update(pointer: fixture.pointerOverNeighbour)

        try await Task.sleep(for: .milliseconds(60))

        XCTAssertTrue(
            fixture.state.isLifted(fixture.item.id),
            "A promoted lift is a live drag and is never written off."
        )
        XCTAssertTrue(
            lockedPager(fixture.state),
            "So the strip keeps holding still under it."
        )

        let drop = fixture.state.end()
        XCTAssertEqual(
            drop?.item,
            fixture.item,
            "And the drop still commits what it was carrying."
        )
    }

    /// Re-staging restarts the clock rather than inheriting the old one.
    func testEachStageGetsItsOwnExpiry() async throws {
        let fixture = ReorderStagingFixture(
            stagedLiftExpiration: .milliseconds(40)
        )

        fixture.state.stage(item: fixture.item, section: fixture.section)
        try await Task.sleep(for: .milliseconds(25))
        fixture.state.stage(item: fixture.item, section: fixture.section)
        try await Task.sleep(for: .milliseconds(25))

        XCTAssertTrue(
            fixture.state.hasLiftInFlight,
            "The second stage is 25ms old and must still be waiting."
        )

        fixture.state.update(pointer: fixture.pointerOverNeighbour)
        XCTAssertTrue(
            fixture.state.isLifted(fixture.item.id),
            "And is still there to be promoted."
        )
    }

    /// The lock reads three sources and any one of them is enough. The sidebar
    /// lift is the one that was missing.
    func testAnyLiftInFlightLocksTheSpaceStrip() {
        let matrix: [(sidebar: Bool, tab: Bool, folder: Bool, locked: Bool)] = [
            (sidebar: false, tab: false, folder: false, locked: false),
            (sidebar: true, tab: false, folder: false, locked: true),
            (sidebar: false, tab: true, folder: false, locked: true),
            (sidebar: false, tab: false, folder: true, locked: true),
        ]

        for entry in matrix {
            XCTAssertEqual(
                BrowserSpacePagerPolicy.isInteractionLocked(
                    hasSidebarLift: entry.sidebar,
                    hasTabDrag: entry.tab,
                    hasFolderDrag: entry.folder
                ),
                entry.locked,
                "sidebar: \(entry.sidebar), tab: \(entry.tab), "
                    + "folder: \(entry.folder)"
            )
        }
    }

    /// What the pager itself computes, from the one state a touch lift touches.
    private func lockedPager(_ state: BrowserSidebarReorderState) -> Bool {
        BrowserSpacePagerPolicy.isInteractionLocked(
            hasSidebarLift: state.hasLiftInFlight,
            hasTabDrag: false,
            hasFolderDrag: false
        )
    }

    /// A menu that opens over a staged lift has to clear the stage.
    ///
    /// Staging happens in `.onDrag`'s provider, which UIKit calls while it is
    /// still deciding between the drag and the menu. When the menu wins there is
    /// no session left to report a phase, so nothing else will ever clear it —
    /// and a stage left behind is promoted by the next position any later drag
    /// reports over the sidebar, lifting a row nobody picked up.
    func testAMenuOpeningOverAStagedLiftClearsIt() {
        let fixture = ReorderStagingFixture()

        fixture.state.stage(item: fixture.item, section: fixture.section)
        fixture.state.yieldToCompetingInteraction()
        fixture.state.update(pointer: fixture.pointerOverNeighbour)

        XCTAssertFalse(
            fixture.state.isDragging,
            "A stage the menu took over must not promote on a later sample."
        )
        XCTAssertNil(fixture.state.resolvedTarget)
        XCTAssertFalse(
            fixture.state.suppressesActivation,
            "No drag ever happened, so the row stays openable."
        )
    }

    /// The same interruption after the lift has promoted, which is the state the
    /// reader can actually see: the lifted row is hidden in its slot and its
    /// neighbours are held aside at their displaced offsets. Nothing restores
    /// them unless the menu says so.
    func testAMenuOpeningOverAPromotedLiftPutsTheRowsBack() {
        let fixture = ReorderStagingFixture()

        fixture.state.stage(item: fixture.item, section: fixture.section)
        fixture.state.update(pointer: fixture.pointerOverNeighbour)
        XCTAssertTrue(fixture.state.isLifted(fixture.item.id))

        fixture.state.yieldToCompetingInteraction()

        XCTAssertFalse(
            fixture.state.isLifted(fixture.item.id),
            "The lifted row has to come back rather than stay invisible."
        )
        XCTAssertEqual(
            fixture.state.displacement(for: fixture.neighbourID),
            .zero,
            "Neighbours have to close the gap rather than stay offset."
        )
        XCTAssertNil(fixture.state.resolvedTarget)
        XCTAssertTrue(
            fixture.state.suppressesActivation,
            "A lift did happen, so the release must not also open the tab."
        )
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

    /// The tile half of the same rule, spelled out for the shell that actually
    /// has the defect.
    ///
    /// `testNoCompactPlacementAnchorsARowWithMatchedGeometry` covers the row.
    /// A pinned tile reaches the same modifier through its own helper, and that
    /// helper kept reading the rule as the bare negation of the native zoom —
    /// so on the docked and floating sidebars every tile wore a partnerless
    /// matched-geometry anchor over the view `.onDrag` lifts, while the tab
    /// viewer's tiles kept working. A pinned tab could be picked up and dropped
    /// nowhere at all; nothing about the reorder machinery was involved.
    func testNoCompactPlacementAnchorsAPinnedTileWithMatchedGeometry() {
        for usesNativeNavigationTransition in [true, false] {
            let capabilities = BrowserInteractionCapabilities(
                supportsHover: true,
                supportsTouch: true,
                showsRowDropIndicators: true,
                reservesReorderSectionZones: true,
                usesNativeNavigationTransition: usesNativeNavigationTransition,
                pairsRowWithPromotedSurface: false
            )

            for isTransitionSource in [true, false] {
                let anchor = BrowserPinnedTabPromotionPolicy.anchor(
                    hasNamespace: true,
                    isTransitionSource: isTransitionSource,
                    capabilities: capabilities
                )
                XCTAssertNotEqual(
                    anchor,
                    .matchedGeometryDestination,
                    "native zoom: \(usesNativeNavigationTransition), "
                        + "source: \(isTransitionSource)"
                )
                // The tab viewer's selected tile is still the zoom's source —
                // that anchor has a partner, and removing it would break the
                // placement that always worked.
                let expected: BrowserPinnedTabPromotionAnchor =
                    usesNativeNavigationTransition && isTransitionSource
                    ? .navigationZoomSource
                    : .none
                XCTAssertEqual(
                    anchor,
                    expected,
                    "native zoom: \(usesNativeNavigationTransition), "
                        + "source: \(isTransitionSource)"
                )
            }
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
        let neighbourID: BrowserSidebarReorderItemID
        let draggedFrame = CGRect(x: 8, y: 110, width: 374, height: 44)
        let neighbourFrame = CGRect(x: 8, y: 154, width: 374, height: 44)

        var pointerOverNeighbour: CGPoint {
            CGPoint(x: neighbourFrame.midX, y: neighbourFrame.midY)
        }

        init(
            stagedLiftExpiration: Duration = BrowserSidebarReorderPolicy
                .stagedLiftExpiration
        ) {
            state = BrowserSidebarReorderState(
                stagedLiftExpiration: stagedLiftExpiration
            )
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
            neighbourID = .tab(TabID())
            state.register(
                row: BrowserSidebarReorderRow(
                    id: neighbourID,
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

    // MARK: - A lift that starts on a pinned tile

    /// Every destination a tile can be carried to, from the one origin that had
    /// no coverage at all.
    ///
    /// The pinned grid sits outside the scrolling list and lays out sideways, so
    /// a tile's lift is the one that exercises grid ordering, the pinned cap, and
    /// a cross-section arrival all from a `.tabs(placement: .pinned, …)` origin.
    /// Nothing asserted that a tile could be carried anywhere, which is how a
    /// pinned tab came to be liftable and undroppable on iPad without a single
    /// test going red.
    func testAPinnedTileCanBeCarriedToEveryRunTheSidebarOffers() {
        let fixture = PinnedOriginFixture()

        fixture.stageTileLift()

        fixture.state.update(pointer: fixture.pointerOverCurrentRun)
        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            .tabs(placement: .current, folderID: nil),
            "A tile carried into the open list must resolve a place in it."
        )

        fixture.state.update(pointer: fixture.pointerOverSavedRun)
        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            .tabs(placement: .saved, folderID: nil),
            "And into the saved list."
        )

        fixture.state.update(pointer: fixture.pointerBetweenPinnedTiles)
        XCTAssertEqual(
            fixture.state.resolvedTarget,
            BrowserSidebarReorderTarget(
                kind: .insert(
                    section: .tabs(placement: .pinned, folderID: nil),
                    beforeID: fixture.tileIDs[2],
                    index: 1
                )
            ),
            "And back into its own grid, ordered across the line it is on "
                + "rather than down it."
        )

        let drop = fixture.state.end()
        XCTAssertEqual(drop?.item, fixture.lift)
        XCTAssertEqual(drop?.target.section, .tabs(placement: .pinned, folderID: nil))
    }

    /// Negative control for the same lift: the Space filter every reader applies
    /// must not exclude the tile's own Space.
    ///
    /// A tile builds its drag item from the grid's Space assignment while a row
    /// builds one from the row's. If those two ever disagree the filter keeps a
    /// tile's lift from seeing a single row, and it resolves nothing anywhere —
    /// the exact shape of the reported defect. The neighbouring Space's rows,
    /// which the pager keeps alive, must stay excluded at the same time.
    func testATileLiftSeesItsOwnSpacesRowsAndOnlyThose() {
        let fixture = PinnedOriginFixture()
        fixture.registerForeignSpaceRun()

        fixture.stageTileLift()
        fixture.state.update(pointer: fixture.pointerOverCurrentRun)

        XCTAssertEqual(
            fixture.state.resolvedTarget,
            BrowserSidebarReorderTarget(
                kind: .insert(
                    section: .tabs(placement: .current, folderID: nil),
                    beforeID: fixture.currentRowIDs[0],
                    index: 0
                )
            ),
            "A neighbouring Space's rows are registered under the same section "
                + "identity, and counting them would put the tile behind rows "
                + "the pointer never passed."
        )
    }

    /// A grid at its cap still takes its own tiles back. `hasRoom` exempts a row
    /// already in the section, and a tile reordering inside a full grid is
    /// exactly that case — the one the cap must not refuse.
    func testAFullPinnedGridStillTakesItsOwnTileBack() {
        let fixture = PinnedOriginFixture(tileCount: BrowserSpace.maximumPinnedTabs)

        fixture.stageTileLift()
        fixture.state.update(pointer: fixture.pointerBetweenPinnedTiles)

        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            .tabs(placement: .pinned, folderID: nil),
            "Reordering inside a full grid consumes no new slot."
        )
    }

    // MARK: - What an open folder says while a drop is aimed at it

    /// An open folder holding nothing had no way to answer a drop.
    ///
    /// Its header carries the group's section zone, so the drop resolves and
    /// commits — but the nesting highlight belongs to a *collapsed* folder, and
    /// an empty run has no row to hand the insertion line to. The folder took
    /// the tab in complete silence, which reads as a refused drag right up until
    /// it lands.
    func testAnOpenEmptyFolderDrawsTheSeamItsRunHasNoRowFor() {
        let fixture = FolderFeedbackFixture()

        fixture.stageTabLift()
        fixture.state.update(pointer: fixture.pointerOverFolderHeader)

        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            fixture.folderSection,
            "The folder group's own run outranks the saved list it nests in."
        )
        XCTAssertEqual(
            fixture.state.emptySectionIndicator(for: fixture.folderSection),
            BrowserSidebarReorderIndicator(
                side: .before,
                flowsHorizontally: false
            ),
            "An empty run inserts at index zero, so the line stands where its "
                + "first row would."
        )
        XCTAssertNil(
            fixture.state.emptySectionIndicator(for: fixture.savedSection),
            "And it belongs to the folder, not to the list around it."
        )
    }

    /// The other half of the same answer: a folder the reader has closed says
    /// "inside this one" by lighting its header up, and that has to resolve from
    /// a touch lift.
    ///
    /// It could not before the shared group landed. The compact shell's folder
    /// header read its highlight from `tabDragState` and an unwired local flag,
    /// and a touch lift populates neither — it stages straight into the reorder
    /// state — so a collapsed folder never lit up on iOS at all.
    func testAClosedFolderLightsUpForATouchLiftAimedInsideIt() {
        let fixture = FolderFeedbackFixture(isFolderCollapsed: true)

        fixture.stageTabLift()
        fixture.state.update(pointer: fixture.pointerOverFolderHeader)

        XCTAssertTrue(
            fixture.state.isTargetedFolder(fixture.folderID),
            "The nesting band of a closed folder's row files the tab inside it."
        )
        XCTAssertTrue(
            BrowserFolderRowPresentationPolicy.showsDropHighlight(
                for: fixture.state.lift?.item
            ),
            "A tab filing into a folder becomes one of its rows, so the header "
                + "wears a row's own selection treatment."
        )
        XCTAssertFalse(
            BrowserFolderRowPresentationPolicy.showsNestOutline(
                for: fixture.state.lift?.item
            ),
            "The outline says 'a folder inside this folder', which a tab is not."
        )
    }

    /// Negative control: with the pointer off the folder entirely, neither
    /// answer is offered.
    func testAFolderSaysNothingWhileTheDropIsAimedElsewhere() {
        let fixture = FolderFeedbackFixture()

        fixture.stageTabLift()
        fixture.state.update(pointer: fixture.pointerOverUnfiledRun)

        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            fixture.savedSection
        )
        XCTAssertNil(
            fixture.state.emptySectionIndicator(for: fixture.folderSection)
        )
        XCTAssertFalse(fixture.state.isTargetedFolder(fixture.folderID))
    }

    /// A tile lift, its grid, and the two lists it can be carried into, measured
    /// the way a compact sidebar lays them out: the pinned grid above the header,
    /// the saved and open runs below it in one scrolling column.
    @MainActor
    private struct PinnedOriginFixture {
        let state = BrowserSidebarReorderState()
        let space = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let pinnedSection = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let savedSection = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        let currentSection = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let lift: BrowserSidebarReorderItem
        private(set) var tileIDs: [BrowserSidebarReorderItemID] = []
        private(set) var currentRowIDs: [BrowserSidebarReorderItemID] = []

        private static let tileSide: CGFloat = 68
        private static let tilePitch: CGFloat = 74
        private static let gridOrigin = CGPoint(x: 12, y: 70)

        var pointerBetweenPinnedTiles: CGPoint {
            // Past the first remaining tile's centre and short of the next
            // one's, on the single line the grid lays out — which is the move
            // only a grid can make and a list cannot.
            CGPoint(
                x: Self.gridOrigin.x + Self.tilePitch + Self.tileSide * 3 / 4,
                y: Self.gridOrigin.y + Self.tileSide / 2
            )
        }
        var pointerOverSavedRun = CGPoint(x: 160, y: 236)
        var pointerOverCurrentRun = CGPoint(x: 160, y: 362)

        init(tileCount: Int = 4) {
            let liftItem = BrowserTabDragItem(
                tabID: TabID(),
                spaceID: space.spaceID,
                profileID: space.profileID
            )
            lift = .tab(liftItem)

            for index in 0..<tileCount {
                let id: BrowserSidebarReorderItemID =
                    index == 0 ? lift.id : .tab(TabID())
                tileIDs.append(id)
                state.register(
                    row: BrowserSidebarReorderRow(
                        id: id,
                        space: space,
                        section: pinnedSection,
                        frame: CGRect(
                            x: Self.gridOrigin.x
                                + CGFloat(index) * Self.tilePitch,
                            y: Self.gridOrigin.y,
                            width: Self.tileSide,
                            height: Self.tileSide
                        )
                    ),
                    owner: UUID()
                )
            }

            for index in 0..<2 {
                state.register(
                    row: BrowserSidebarReorderRow(
                        id: .tab(TabID()),
                        space: space,
                        section: savedSection,
                        frame: CGRect(
                            x: 8,
                            y: 220 + CGFloat(index) * 44,
                            width: 304,
                            height: 44
                        )
                    ),
                    owner: UUID()
                )
            }

            for index in 0..<2 {
                let id = BrowserSidebarReorderItemID.tab(TabID())
                currentRowIDs.append(id)
                state.register(
                    row: BrowserSidebarReorderRow(
                        id: id,
                        space: space,
                        section: currentSection,
                        frame: CGRect(
                            x: 8,
                            y: 340 + CGFloat(index) * 44,
                            width: 304,
                            height: 44
                        )
                    ),
                    owner: UUID()
                )
            }

            register(zone: .section(pinnedSection), frame: pinnedZone)
            register(
                zone: .section(savedSection),
                frame: CGRect(x: 0, y: 200, width: 320, height: 110)
            )
            register(
                zone: .section(currentSection),
                frame: CGRect(x: 0, y: 320, width: 320, height: 110)
            )
        }

        /// A second Space's pinned grid and open list, which the Space pager
        /// keeps alive either side of the visible page and which register under
        /// the very same section identities.
        func registerForeignSpaceRun() {
            let foreign = BrowserSpaceRuntimeAssignment(
                spaceID: SpaceID(),
                profileID: space.profileID
            )
            for index in 0..<3 {
                state.register(
                    row: BrowserSidebarReorderRow(
                        id: .tab(TabID()),
                        space: foreign,
                        section: currentSection,
                        frame: CGRect(
                            x: 8,
                            y: 340 + CGFloat(index) * 44,
                            width: 304,
                            height: 44
                        )
                    ),
                    owner: UUID()
                )
            }
        }

        /// Stage then promote, the way the compact shell's `.onDrag` and its
        /// drop delegate do between them.
        func stageTileLift() {
            state.stage(item: lift, section: pinnedSection)
        }

        private var pinnedZone: CGRect {
            CGRect(x: 0, y: 60, width: 320, height: Self.tileSide + 20)
        }

        private func register(
            zone target: BrowserSidebarReorderZone.Target,
            frame: CGRect
        ) {
            state.register(
                zone: BrowserSidebarReorderZone(target: target, frame: frame),
                for: UUID()
            )
        }
    }

    /// One empty folder in a saved list that also holds an unfiled row, measured
    /// the way the compact sidebar lays it out.
    @MainActor
    private struct FolderFeedbackFixture {
        let state = BrowserSidebarReorderState()
        let folderID = FolderID()
        let space = BrowserSpaceRuntimeAssignment(
            spaceID: SpaceID(),
            profileID: UUID()
        )
        let lift: BrowserSidebarReorderItem
        let savedSection = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        var folderSection: BrowserSidebarReorderSection {
            .tabs(placement: .saved, folderID: folderID)
        }

        /// The whole group while the folder is closed: its header and nothing
        /// else, because it holds nothing.
        private let folderGroupFrame = CGRect(x: 0, y: 200, width: 320, height: 44)

        var pointerOverFolderHeader: CGPoint {
            CGPoint(x: folderGroupFrame.midX, y: folderGroupFrame.midY)
        }
        var pointerOverUnfiledRun = CGPoint(x: 160, y: 288)

        init(isFolderCollapsed: Bool = false) {
            let liftItem = BrowserTabDragItem(
                tabID: TabID(),
                spaceID: space.spaceID,
                profileID: space.profileID
            )
            lift = .tab(liftItem)

            let unfiledFrame = CGRect(x: 8, y: 266, width: 304, height: 44)
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(TabID()),
                    space: space,
                    section: savedSection,
                    frame: unfiledFrame
                ),
                owner: UUID()
            )

            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(savedSection),
                    frame: CGRect(x: 0, y: 190, width: 320, height: 130)
                ),
                for: UUID()
            )
            // The folder group's own run, which spans the header — which is what
            // lets a drop land in an open folder that has no rows to aim at.
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(folderSection),
                    frame: folderGroupFrame
                ),
                for: UUID()
            )
            if isFolderCollapsed {
                state.register(
                    zone: BrowserSidebarReorderZone(
                        target: .folder(folderID),
                        frame: BrowserSidebarReorderPolicy.nestingFrame(
                            for: folderGroupFrame
                        )
                    ),
                    for: UUID()
                )
            }
        }

        func stageTabLift() {
            state.stage(item: lift, section: savedSection)
        }
    }

    // MARK: - A lift carried onto the page

    /// Drag-to-split, from the touch shell's own three-piece contract: `.onDrag`
    /// stages, the first reported position promotes, and the position that
    /// promotes may be one the *page* reported rather than the sidebar.
    ///
    /// That last part is the whole of what iPadOS was missing. macOS streams its
    /// lift from a `DragGesture` that keeps reporting wherever the pointer goes,
    /// so the page needs no feed of its own; a touch lift hears only from the
    /// drop interactions it passes over, and there was none over the content
    /// area at all — a finger that left the sidebar went dark, and the cards on
    /// show could not be joined.
    func testAPositionReportedOverThePagePromotesTheLiftAndResolvesACardSlot() {
        let fixture = PadContentAreaFixture(cardCount: 2)
        fixture.register()

        fixture.stageTheLift()
        XCTAssertFalse(
            fixture.state.isDragging,
            "Staging alone lifts nothing, on the page as anywhere else."
        )

        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 1))

        XCTAssertTrue(
            fixture.state.isDragging,
            "The content area's feed reports positions like any other, so the "
                + "sample that arrives from it must promote the staged lift."
        )
        XCTAssertEqual(
            fixture.state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 1),
            "Past the first card and short of the second's midpoint is the "
                + "seam between them."
        )
        XCTAssertEqual(fixture.state.liftTargetShape, .webpageCard)
        XCTAssertTrue(fixture.state.hasEnteredSplitContent)
    }

    /// The lone tab on show is a card, which is how an iPad presenting one page
    /// becomes a split at all: its leading half puts the new card in front of it
    /// and its trailing half behind.
    func testTheLoneTabOnShowSplitsIntoALeadingAndATrailingHalf() {
        let fixture = PadContentAreaFixture(cardCount: 1)
        fixture.register()

        fixture.stageTheLift()
        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 0))
        XCTAssertEqual(
            fixture.state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 0)
        )

        fixture.state.update(pointer: fixture.pointInTrailingHalf(ofCard: 0))
        XCTAssertEqual(
            fixture.state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 1)
        )
    }

    /// A sidebar the reader has undocked is drawn *on top of* the page, so the
    /// content zone spans the whole window and every sidebar run overlaps it.
    /// The runs still win, including the seams between them — which is the only
    /// way a narrow iPad's lists stay reachable while the page offers itself.
    func testAFloatingSidebarDrawnOverThePageKeepsItsOwnRuns() {
        let fixture = PadContentAreaFixture(
            cardCount: 2,
            sidebarIsFloating: true
        )
        fixture.register()

        fixture.stageTheLift()

        fixture.state.update(pointer: fixture.pointInTheOpenList)
        XCTAssertEqual(
            fixture.state.resolvedTarget?.section,
            fixture.section,
            "A run under the finger outranks the page behind it."
        )

        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 1))
        XCTAssertEqual(
            fixture.state.resolvedTarget?.kind,
            .splitInsert(assignment: fixture.assignment, index: 1),
            "Past the floating card there is nothing else to outrank it."
        )
    }

    /// Negative control for the zone. Before this shell registered one, the page
    /// was not a drop target on iPadOS at all: the cards were measured — the
    /// columns view has always laid them out — but nothing named the area they
    /// sat in, so the very same sample resolved nowhere.
    func testWithoutTheContentZoneTheSameSampleResolvesNothing() {
        let fixture = PadContentAreaFixture(cardCount: 2)
        fixture.registerCardsOnly()

        fixture.stageTheLift()
        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 1))

        XCTAssertNil(
            fixture.state.resolvedTarget,
            "No zone names the content area, so the finger is over nothing."
        )
        XCTAssertFalse(fixture.state.hasEnteredSplitContent)
    }

    /// Negative control for the card frames. A zone on its own promises an area
    /// with nothing in it to join, and the state refuses rather than offering a
    /// slot the commit would decline.
    func testWithoutRegisteredCardsTheContentZoneResolvesNothing() {
        let fixture = PadContentAreaFixture(cardCount: 2)
        fixture.registerZoneOnly()

        fixture.stageTheLift()
        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 1))

        XCTAssertNil(
            fixture.state.resolvedTarget,
            "Nothing is presented as far as the registry knows, so there is no "
                + "card to join."
        )
        XCTAssertFalse(fixture.state.hasEnteredSplitContent)
    }

    /// The Space strip holds still for a lift that has left the sidebar as well.
    ///
    /// Carrying a tab across the page is exactly the stretch where a finger
    /// travels furthest, and the strip pages on horizontal movement — so a lock
    /// that only covered the sidebar would swap the Space out from under the
    /// very cards the drop is aimed at.
    func testTheSpaceStripStaysLockedWhileTheFingerIsOverThePage() {
        let fixture = PadContentAreaFixture(cardCount: 2)
        fixture.register()

        fixture.stageTheLift()
        XCTAssertTrue(lockedPager(fixture.state))

        fixture.state.update(pointer: fixture.pointInLeadingHalf(ofCard: 1))
        XCTAssertTrue(
            lockedPager(fixture.state),
            "A lift over the page is still a lift in flight."
        )

        _ = fixture.state.end()
        XCTAssertFalse(lockedPager(fixture.state))
    }

    /// The release, end to end: what the touch shell's drop delegate does when
    /// the finger lets go over the page, through the shared commit.
    ///
    /// A lone tab on show and a tab dropped on its trailing half is the gesture
    /// that creates a split, and the session has to come out of it holding a
    /// group of the two in that order.
    func testAReleaseOverTheLoneCardCommitsTheSplitTheDragPromised() throws {
        let fixture = PadContentAreaFixture(cardCount: 1)
        fixture.register()

        fixture.stageTheLift()
        fixture.state.update(pointer: fixture.pointInTrailingHalf(ofCard: 0))

        let drop = try XCTUnwrap(fixture.state.end())
        fixture.commit(drop)

        let space = try XCTUnwrap(fixture.browser.selectedSpace)
        let groupID = try XCTUnwrap(space.splitGroup(containing: fixture.cards[0].id))
        XCTAssertEqual(
            space.splitGroupMembers(of: groupID).map(\.id),
            [fixture.cards[0].id, fixture.joiner.id],
            "Dropped on the trailing half, the carried tab lands behind the "
                + "card that was already there."
        )
        XCTAssertFalse(
            fixture.state.hasEnteredSplitContent,
            "The drop ends the drag, so the layout latch it opened stands down."
        )
    }

    /// The iPad content area, measured the way the shell lays it out: the detail
    /// column beside a docked sidebar — or the whole window with one floating
    /// over it — the page insets `BrowserSplitColumnsView` applies, and the cards
    /// `BrowserSplitColumnLayout` shares the remainder between.
    @MainActor
    private struct PadContentAreaFixture {
        let browser: BrowserStore
        let spaceAccess = BrowserSpaceAccessController()
        let cards: [BrowserTab]
        let joiner: BrowserTab
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )

        private let sidebarIsFloating: Bool
        private let spaceID = SpaceID(rawValue: padUUID(0x01))
        private let profileID = padUUID(0x02)

        /// A 13-inch iPad in landscape, with the sidebar width the shell defaults
        /// to for that width.
        private static let windowSize = CGSize(width: 1_210, height: 834)
        private static let sidebarWidth: CGFloat = 280
        private static let joinerRow = CGRect(x: 12, y: 300, width: 256, height: 44)

        init(cardCount: Int, sidebarIsFloating: Bool = false) {
            self.sidebarIsFloating = sidebarIsFloating
            cards = (0..<cardCount).map { index in
                padTab(
                    id: TabID(rawValue: padUUID(UInt8(0x10 + index))),
                    title: "Card \(index)"
                )
            }
            joiner = padTab(
                id: TabID(rawValue: padUUID(0x30)),
                title: "Joiner"
            )
            let space = BrowserSpace(
                id: spaceID,
                profile: BrowsingProfile(id: profileID),
                name: "Reading",
                symbol: "rectangle.stack",
                accent: .indigo,
                folders: [],
                tabs: cards + [joiner],
                selectedTabID: cards.first?.id ?? joiner.id
            )
            browser = BrowserStore(
                session: BrowserSession(
                    spaces: [space],
                    selectedSpaceID: space.id
                ),
                persistence: InMemoryBrowserSessionPersistence(),
                browsingMode: .privateBrowsing
            )
        }

        var state: BrowserSidebarReorderState { browser.sidebarReorderState }

        var assignment: BrowserSpaceRuntimeAssignment {
            BrowserSpaceRuntimeAssignment(spaceID: spaceID, profileID: profileID)
        }

        /// What `MobileRegularPageSurface` offers as a zone: the whole detail
        /// column, insets included. A floating sidebar is drawn over the page, so
        /// the detail column is then the whole window.
        var contentZone: CGRect {
            sidebarIsFloating
                ? CGRect(origin: .zero, size: Self.windowSize)
                : CGRect(
                    x: Self.sidebarWidth,
                    y: 0,
                    width: Self.windowSize.width - Self.sidebarWidth,
                    height: Self.windowSize.height
                )
        }

        /// The run the sidebar puts its open list in, which a floating card draws
        /// on top of the page.
        var sidebarZone: CGRect {
            CGRect(x: 8, y: 260, width: Self.sidebarWidth - 16, height: 420)
        }

        var pointInTheOpenList: CGPoint {
            CGPoint(x: sidebarZone.midX, y: sidebarZone.midY)
        }

        func pointInLeadingHalf(ofCard index: Int) -> CGPoint {
            let card = cardFrames[index]
            return CGPoint(x: card.minX + card.width / 4, y: card.midY)
        }

        func pointInTrailingHalf(ofCard index: Int) -> CGPoint {
            let card = cardFrames[index]
            return CGPoint(x: card.maxX - card.width / 4, y: card.midY)
        }

        /// Where the columns row puts each card: the zone less the page insets,
        /// shared into equal columns with the row's own gap between them.
        var cardFrames: [CGRect] {
            let insets = BrowserChromeLayout.pageFrameInsets(
                adjoinsLeadingSidebar: !sidebarIsFloating
            )
            let row = CGRect(
                x: contentZone.minX + insets.leading,
                y: contentZone.minY + insets.top,
                width: contentZone.width - insets.leading - insets.trailing,
                height: contentZone.height - insets.top - insets.bottom
            )
            let widths = BrowserSplitColumnLayout.widths(
                containerWidth: row.width,
                fractions: BrowserSplitLayoutSeedPolicy.fractions(
                    persisted: nil,
                    memberCount: cards.count
                )
            )
            var leading = row.minX
            return widths.map { width in
                defer {
                    leading += width + BrowserSplitLayoutMetrics.interCardGap
                }
                return CGRect(
                    x: leading,
                    y: row.minY,
                    width: width,
                    height: row.height
                )
            }
        }

        /// Everything the iPad shell registers once this lands: the sidebar's own
        /// run, the content area as a zone, and one frame per presented card.
        func register() {
            registerSidebar()
            registerZone()
            registerCards()
        }

        /// The shell as it stood before: cards measured, no zone naming the area
        /// they sit in.
        func registerCardsOnly() {
            registerSidebar()
            registerCards()
        }

        func registerZoneOnly() {
            registerSidebar()
            registerZone()
        }

        func stageTheLift() {
            state.stage(item: liftItem, section: section)
        }

        func commit(
            _ drop: (
                item: BrowserSidebarReorderItem,
                target: BrowserSidebarReorderTarget
            )
        ) {
            BrowserSidebarReorderContext(
                browser: browser,
                spaceAccess: spaceAccess
            )
            .commit(drop.target, for: drop.item)
        }

        private var liftItem: BrowserSidebarReorderItem {
            .tab(
                BrowserTabDragItem(
                    tabID: joiner.id,
                    spaceID: spaceID,
                    profileID: profileID
                )
            )
        }

        private func registerSidebar() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: liftItem.id,
                    space: assignment,
                    section: section,
                    frame: Self.joinerRow
                ),
                owner: UUID()
            )
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .section(section),
                    frame: sidebarZone
                ),
                for: UUID()
            )
        }

        private func registerZone() {
            state.register(
                zone: BrowserSidebarReorderZone(
                    target: .splitContent(assignment),
                    frame: contentZone
                ),
                for: UUID()
            )
        }

        private func registerCards() {
            for (card, frame) in zip(cards, cardFrames) {
                state.register(
                    splitCardFrame: frame,
                    for: card.id,
                    in: assignment,
                    owner: UUID()
                )
            }
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
