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
            tabs: tabs
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
