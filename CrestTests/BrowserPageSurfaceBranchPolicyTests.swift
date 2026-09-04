import Foundation
import XCTest

@testable import Crest

/// The branch both content areas draw from. Every case here is one the two
/// shells used to answer separately, so the assertions are on exact values: a
/// divergence would show up as one platform opening columns where the other
/// keeps a single surface, which is a different host for the same live page.
final class BrowserPageSurfaceBranchPolicyTests: XCTestCase {
    func testLoneTabWithPanelUsesColumnsButEmptyAndLockedSpacesDoNot() {
        let tab = makeTab("Only")
        let space = makeSpace(tabs: [tab])
        XCTAssertEqual(
            BrowserPageSurfaceBranchPolicy.resolve(
                selectedSpace: space, isSelectedSpaceLocked: false,
                selectedTabID: tab.id, hasEnteredSplitContent: false,
                resolvedTarget: nil, presentsTrailingPanel: true
            ), .columns(space: space, members: [tab], placeholderIndex: nil))
        XCTAssertEqual(
            BrowserPageSurfaceBranchPolicy.resolve(
                selectedSpace: space, isSelectedSpaceLocked: true,
                selectedTabID: tab.id, hasEnteredSplitContent: false,
                resolvedTarget: nil, presentsTrailingPanel: true
            ), .unavailable)
        let empty = makeSpace(tabs: [])
        XCTAssertEqual(
            BrowserPageSurfaceBranchPolicy.resolve(
                selectedSpace: empty, isSelectedSpaceLocked: false,
                selectedTabID: nil, hasEnteredSplitContent: false,
                resolvedTarget: nil, presentsTrailingPanel: true
            ), .single(space: empty, cardTabID: nil))
    }

    func testNoSelectedSpacePresentsNothingToDropInto() {
        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: nil,
            isSelectedSpaceLocked: false,
            selectedTabID: TabID(),
            hasEnteredSplitContent: false,
            resolvedTarget: nil
        )

        XCTAssertEqual(presentation, .unavailable)
        XCTAssertNil(presentation.presentingSpace)
        XCTAssertNil(presentation.dropAssignment)
        XCTAssertNil(presentation.singleCardTabID)
    }

    func testALockedSpaceIsExcludedEvenWithAFullGroupSelected() {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: true,
            selectedTabID: head.id,
            hasEnteredSplitContent: false,
            resolvedTarget: nil
        )

        XCTAssertEqual(
            presentation,
            .unavailable,
            "A lock gate must not leave half a split on screen behind it."
        )
        XCTAssertNil(presentation.dropAssignment)
    }

    func testALoneTabPresentsTheSingleSurfaceAsItsOwnDropCard() {
        let only = makeTab("Only")
        let space = makeSpace(tabs: [only])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: only.id,
            hasEnteredSplitContent: false,
            resolvedTarget: nil
        )

        XCTAssertEqual(presentation, .single(space: space, cardTabID: only.id))
        XCTAssertEqual(presentation.singleCardTabID, only.id)
        XCTAssertEqual(
            presentation.dropAssignment,
            BrowserSpaceRuntimeAssignment(space: space)
        )
    }

    func testSingleSurfaceKeepsTheTabChosenByItsPresentation() {
        let first = makeTab("First")
        let second = makeTab("Second")
        var space = makeSpace(tabs: [first, second])
        let presentation = BrowserPageSurfacePresentation.single(
            space: space,
            cardTabID: second.id
        )

        space.selectedTabID = first.id
        space.tabs.removeAll { $0.id == second.id }

        XCTAssertEqual(presentation.singleTab, second)
        XCTAssertEqual(presentation.presentingSpace?.profile.id, space.profile.id)
    }

    func testColumnsAndUnavailableSurfacesCannotSupplyASinglePage() {
        let tab = makeTab("Column")
        let columns = BrowserPageSurfacePresentation.columns(
            space: makeSpace(tabs: [tab]),
            members: [tab],
            placeholderIndex: nil
        )

        XCTAssertNil(columns.singleTab)
        XCTAssertNil(BrowserPageSurfacePresentation.unavailable.singleTab)
    }

    func testMissingSingleTabDoesNotFallBackToTheSpaceSelection() {
        let tab = makeTab("Selected")
        let presentation = BrowserPageSurfacePresentation.single(
            space: makeSpace(tabs: [tab]),
            cardTabID: TabID()
        )

        XCTAssertNil(presentation.singleTab)
    }

    func testAGroupOfMoreThanOneMemberOpensColumnsInSessionOrder() {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let outsider = makeTab("Outsider")
        let space = makeSpace(tabs: [head, tail, outsider])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: tail.id,
            hasEnteredSplitContent: false,
            resolvedTarget: nil
        )

        XCTAssertEqual(
            presentation,
            .columns(
                space: space,
                members: [head, tail],
                placeholderIndex: nil
            )
        )
        XCTAssertNil(presentation.singleCardTabID)
    }

    /// A run shorter than the renderable minimum keeps its stored group ID so a
    /// staggered sync can reconstitute the group. Until the siblings arrive it
    /// is a plain tab, and `presentedSplitMembers(for:)` is the only accessor
    /// that knows the difference.
    func testALoneStoredGroupMemberStaysOnTheSingleSurface() {
        let group = SplitGroupID()
        let orphan = makeTab("Orphan", group: group)
        let space = makeSpace(tabs: [orphan])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: orphan.id,
            hasEnteredSplitContent: false,
            resolvedTarget: nil
        )

        XCTAssertEqual(
            presentation,
            .single(space: space, cardTabID: orphan.id)
        )
    }

    func testADragThatReachedTheContentAreaOpensColumnsAroundOneTab() {
        let only = makeTab("Only")
        let space = makeSpace(tabs: [only])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: only.id,
            hasEnteredSplitContent: true,
            resolvedTarget: nil
        )

        XCTAssertEqual(
            presentation,
            .columns(space: space, members: [only], placeholderIndex: nil),
            "Entering is a one-way door for the drag, but the placeholder "
                + "still comes and goes with the resolved target."
        )
    }

    func testAnEmptySpaceStaysOnTheSingleSurfaceThroughADrag() {
        let space = makeSpace(tabs: [])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: nil,
            hasEnteredSplitContent: true,
            resolvedTarget: nil
        )

        XCTAssertEqual(presentation, .single(space: space, cardTabID: nil))
    }

    func testASplitInsertAimedAtThisSpaceOpensThePlaceholderSlot() {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: head.id,
            hasEnteredSplitContent: true,
            resolvedTarget: BrowserSidebarReorderTarget(
                kind: .splitInsert(
                    assignment: BrowserSpaceRuntimeAssignment(space: space),
                    index: 1
                )
            )
        )

        XCTAssertEqual(
            presentation,
            .columns(space: space, members: [head, tail], placeholderIndex: 1)
        )
    }

    func testASplitInsertAimedAtAnotherSpaceOpensNoSlotHere() {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])
        let elsewhere = makeSpace(name: "Elsewhere", tabs: [])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: head.id,
            hasEnteredSplitContent: true,
            resolvedTarget: BrowserSidebarReorderTarget(
                kind: .splitInsert(
                    assignment: BrowserSpaceRuntimeAssignment(space: elsewhere),
                    index: 0
                )
            )
        )

        XCTAssertEqual(
            presentation,
            .columns(
                space: space,
                members: [head, tail],
                placeholderIndex: nil
            )
        )
    }

    func testANonSplitDropTargetOpensNoSlot() {
        let group = SplitGroupID()
        let head = makeTab("Head", group: group)
        let tail = makeTab("Tail", group: group)
        let space = makeSpace(tabs: [head, tail])

        let presentation = BrowserPageSurfaceBranchPolicy.resolve(
            selectedSpace: space,
            isSelectedSpaceLocked: false,
            selectedTabID: head.id,
            hasEnteredSplitContent: true,
            resolvedTarget: BrowserSidebarReorderTarget(
                kind: .space(BrowserSpaceRuntimeAssignment(space: space))
            )
        )

        XCTAssertEqual(
            presentation,
            .columns(
                space: space,
                members: [head, tail],
                placeholderIndex: nil
            )
        )
    }

    private func makeSpace(
        name: String = "Work",
        tabs: [BrowserTab]
    ) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(),
            profile: BrowsingProfile(),
            name: name,
            symbol: "briefcase.fill",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            selectedTabID: tabs.first?.id
        )
    }

    private func makeTab(
        _ title: String,
        group: SplitGroupID? = nil
    ) -> BrowserTab {
        BrowserTab(
            title: title,
            url: URL(string: "https://example.com/\(title)"),
            placement: .current,
            splitGroupID: group,
            lastActivatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
