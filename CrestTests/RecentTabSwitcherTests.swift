import AppKit
import XCTest

@testable import Crest

@MainActor
final class RecentTabSwitcherTests: XCTestCase {
    // MARK: - Types

    private struct Context {
        let browser: BrowserStore
        let space: SpaceState.Seed
        let target: TabState.Seed
        let companion: TabState.Seed
        let shown: TabState.Seed
        let item: RecentTabItem
        let action: RecentTabSwitcherCloseAction
    }

    // MARK: - Actions - Input

    func testControlWTargetsTheHighlightOnlyWhileTheControlSwitcherShows() throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let items = [first, second, third].map { RecentTabItem(tabIDs: [$0], focusedTabID: $0) }
        let binding = BrowserShortcut(key: .special(.tab), modifiers: .control)
        var session = try XCTUnwrap(
            RecentTabSwitcherSession(direction: .forward, binding: binding, otherBinding: nil, items: items))
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{17}", charactersIgnoringModifiers: "w",
                isARepeat: false, keyCode: 13))
        let close = try XCTUnwrap(BrowserShortcut(event: event))
        XCTAssertNil(session.keyDown(close).itemToClose)
        XCTAssertNil(session.showDelayElapsed(modifiers: .control))
        let response = session.keyDown(close)
        XCTAssertTrue(response.isConsumed)
        XCTAssertNil(response.outcome)
        XCTAssertEqual(response.itemToClose, items[1])
        XCTAssertEqual(session.highlightedItem, items[1], "A request alone must not remove the item")
        for modifiers: ShortcutModifiers in [
            .command, [.control, .shift], [.control, .option], [.control, .command],
        ] {
            XCTAssertNil(session.keyDown(BrowserShortcut(key: .character("w"), modifiers: modifiers)).itemToClose)
        }
        XCTAssertNil(session.refresh(items: [items[0], items[2]]))
        XCTAssertEqual(session.highlightedItem, items[2])
        XCTAssertEqual(session.modifiersChanged(to: []), .commit(items[2]))
        XCTAssertNil(session.refresh(items: [items[0]]))
        XCTAssertEqual(session.modifiersChanged(to: []), .cancel)
        XCTAssertEqual(session.refresh(items: []), .cancel)

        var custom = try XCTUnwrap(
            RecentTabSwitcherSession(
                direction: .forward, binding: BrowserShortcut(key: .special(.tab), modifiers: .option),
                otherBinding: nil, items: items))
        XCTAssertNil(custom.showDelayElapsed(modifiers: .option))
        XCTAssertNil(custom.keyDown(close).itemToClose)
    }

    func testClosedDurableTabsStayOutOfTheHoldAndCurrentSplitSurvivorsRemain() throws {
        let shown = UUID()
        let closed = UUID()
        let companion = UUID()
        let next = UUID()
        let items = [
            RecentTabItem(tabIDs: [shown], focusedTabID: shown),
            RecentTabItem(tabIDs: [closed, companion], focusedTabID: closed),
            RecentTabItem(tabIDs: [next], focusedTabID: next),
        ]
        let binding = BrowserShortcut(key: .special(.tab), modifiers: .control)
        var session = try XCTUnwrap(
            RecentTabSwitcherSession(direction: .forward, binding: binding, otherBinding: nil, items: items))
        XCTAssertNil(session.didCloseTab(closed, items: items))
        XCTAssertEqual(session.highlightedItem, items[2])
        XCTAssertNil(session.refresh(items: items))
        XCTAssertEqual(session.items, [items[0], items[2]])
        let survivor = RecentTabItem(tabIDs: [companion], focusedTabID: companion)
        XCTAssertNil(session.refresh(items: [items[0], survivor, items[2]]))
        XCTAssertTrue(session.items.contains(survivor))
        XCTAssertEqual(session.highlightedItem, items[2])
    }

    // MARK: - Actions - Closing

    func testCloseTargetsTheFocusedSplitMemberAndPreservesDurableTabs() throws {
        for placement: TabPlacement in [.current, .saved, .pinned] {
            let context = try makeContext(placement: placement)
            let expectedTabs = placement.holdsSplits ? [context.target.id, context.companion.id] : [context.target.id]
            XCTAssertEqual(Set(context.item.tabIDs), Set(expectedTabs))
            XCTAssertTrue(context.action.perform(context.item, in: BrowserSpaceRuntimeAssignment(space: context.space)))
            let space = try XCTUnwrap(context.browser.shownSpace)
            XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
            XCTAssertTrue(space.tabs.contains(context.companion.id))
            XCTAssertTrue(space.tabs.contains(context.shown.id))
            XCTAssertEqual(space.tabs.contains(context.target.id), placement.isDurable)
            XCTAssertEqual(space.archive.contains(tabID: context.target.id), !placement.isDurable)
            if placement.isDurable {
                XCTAssertEqual(space.tabs.model(context.target.id)?.placement, placement)
            }
        }
    }

    func testBeforeUnloadCancellationKeepsTheHighlightAndApprovalClosesOnlyItsTab() throws {
        for placement: TabPlacement in [.current, .saved, .pinned] {
            let context = try makeContext(placement: placement)
            let gate = DeferredDismissal()
            context.browser.family.pageDismissalAuthorizer = gate
            let original = context.browser.sessionSeed
            let assignment = BrowserSpaceRuntimeAssignment(space: context.space)
            XCTAssertFalse(context.action.perform(context.item, in: assignment))
            XCTAssertEqual(gate.assignments.map(\.tabID), [context.target.id])
            XCTAssertFalse(gate.resolve(false))
            XCTAssertEqual(context.browser.sessionSeed, original)
            XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
            XCTAssertFalse(context.action.perform(context.item, in: assignment))
            XCTAssertTrue(gate.resolve(true))
            XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
            XCTAssertTrue(context.browser.shownSpace?.tabs.contains(context.companion.id) == true)
        }
    }

    func testDeferredCloseDoesNotCrossSpaceOrProfileChanges() throws {
        let context = try makeContext(placement: .current)
        let assignment = BrowserSpaceRuntimeAssignment(space: context.space)
        XCTAssertFalse(
            context.action.perform(
                context.item, in: BrowserSpaceRuntimeAssignment(spaceID: assignment.spaceID, profileID: UUID())))
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        XCTAssertFalse(context.action.perform(context.item, in: assignment))
        let other = try XCTUnwrap(context.browser.spaceModels.first { $0.id != context.space.id })
        context.browser.selectPresentedSpace(other.id)
        XCTAssertFalse(gate.resolve(true))
        XCTAssertTrue(context.browser.spaceModel(context.space.id)?.tabs.contains(context.target.id) == true)
    }

    // MARK: - Actions - Fixtures

    private func makeContext(placement: TabPlacement) throws -> Context {
        let group = placement.holdsSplits ? UUID() : nil
        let url = try XCTUnwrap(URL(string: "https://example.com/page"))
        let target = TabState.Seed(title: "Target", url: url, placement: placement, splitGroupID: group)
        let companion = TabState.Seed(title: "Companion", url: url, placement: placement, splitGroupID: group)
        let shown = TabState.Seed(title: "Shown", url: url, placement: .current)
        let space = SpaceState.Seed(
            name: "Test", symbol: "circle", accent: .indigo, folders: [], tabs: [target, companion, shown])
        let other = SpaceState.Seed(
            name: "Other", symbol: "circle", accent: .indigo, folders: [],
            tabs: [TabState.Seed(title: "Other", url: url, placement: .current)])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space, other]), showing: space.id, tabs: [space.id: target.id])
        browser.selectTab(shown.id)
        let item = try XCTUnwrap(browser.recentTabItems().first { $0.focusedTabID == target.id })
        let access = BrowserSpaceAccessController()
        access.attach(browser)
        return Context(
            browser: browser, space: space, target: target, companion: companion, shown: shown,
            item: item, action: RecentTabSwitcherCloseAction(browser: browser, spaceAccess: access))
    }
}

@MainActor
private final class DeferredDismissal: BrowserPageDismissalAuthorizing {
    // MARK: - Variables

    private var operation: (@MainActor () -> Bool)?
    private(set) var assignments: [BrowserTabRuntimeAssignment] = []

    // MARK: - Actions - Dismissal

    func performDismissal(
        of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
        operation: @escaping @MainActor () -> Bool
    ) -> Bool {
        self.assignments = assignments
        self.operation = operation
        return false
    }

    func resolve(_ allowed: Bool) -> Bool {
        let pending = operation
        operation = nil
        return allowed && pending?() == true
    }
}
