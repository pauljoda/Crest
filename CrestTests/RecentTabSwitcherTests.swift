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

    func testControlWRequestsTheHighlightedTabOnlyWhileVisible() throws {
        let items = (0..<5).map { _ in
            let id = UUID()
            return RecentTabItem(tabIDs: [id], focusedTabID: id)
        }
        let binding = BrowserShortcut(key: .special(.tab), modifiers: .control)
        var session = try XCTUnwrap(
            RecentTabSwitcherSession(direction: .forward, binding: binding, otherBinding: nil, items: items))
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
                windowNumber: 0, context: nil, characters: "\u{17}", charactersIgnoringModifiers: "w",
                isARepeat: false, keyCode: 13))
        let close = try XCTUnwrap(BrowserShortcut(event: event))
        XCTAssertNil(session.keyDown(close).outcome)
        XCTAssertNil(session.keyDown(close).itemToClose)
        XCTAssertNil(session.showDelayElapsed(modifiers: .control))
        let response = session.keyDown(close)
        XCTAssertTrue(response.isConsumed)
        XCTAssertNil(response.outcome)
        XCTAssertEqual(response.itemToClose, items[1])
        XCTAssertEqual(session.items, items, "A close request must wait for page approval")
        XCTAssertNil(session.closeCompleted(items[1], succeeded: true))
        XCTAssertEqual(session.items, [items[0], items[2], items[3], items[4]])
        XCTAssertEqual(session.highlightedIndex, 1)
        XCTAssertEqual(session.highlightedItem, items[2])
        XCTAssertTrue(session.isShowing)
        XCTAssertNil(session.keyDown(close, isRepeat: true).outcome)
        XCTAssertNil(session.keyDown(close, isRepeat: true).itemToClose)
        for modifiers: ShortcutModifiers in [[.control, .shift], [.control, .option], [.control, .command]] {
            XCTAssertNil(session.keyDown(BrowserShortcut(key: .character("w"), modifiers: modifiers)).itemToClose)
        }
        XCTAssertEqual(session.items, [items[0], items[2], items[3], items[4]])
        XCTAssertNil(session.modifiersChanged(to: .control))
        XCTAssertEqual(session.modifiersChanged(to: []), .commit(items[2]))

        var custom = try XCTUnwrap(
            RecentTabSwitcherSession(
                direction: .forward, binding: BrowserShortcut(key: .special(.tab), modifiers: .option),
                otherBinding: nil, items: items))
        XCTAssertNil(custom.showDelayElapsed(modifiers: .option))
        XCTAssertNil(custom.keyDown(close).itemToClose)
    }

    func testImmediateClosesKeepTheirOrderAndEndTheEmptySwitcher() throws {
        let items = (0..<5).map { _ in
            let id = UUID()
            return RecentTabItem(tabIDs: [id], focusedTabID: id)
        }
        let binding = BrowserShortcut(key: .special(.tab), modifiers: .control)
        let close = BrowserShortcut(key: .character("w"), modifiers: .control)
        var session = try XCTUnwrap(
            RecentTabSwitcherSession(direction: .forward, binding: binding, otherBinding: nil, items: items))
        XCTAssertNil(session.showDelayElapsed(modifiers: .control))
        for index in 1..<5 {
            XCTAssertTrue(session.presentsPanel)
            XCTAssertEqual(session.highlightedItem, items[index])
            XCTAssertEqual(session.keyDown(close).itemToClose, items[index])
            XCTAssertNil(session.closeCompleted(items[index], succeeded: true))
            XCTAssertNil(session.refresh(items: Array(items.reversed())))
            XCTAssertEqual(session.items, [items[0]] + Array(items.dropFirst(index + 1)))
        }
        XCTAssertEqual(session.highlightedItem, items[0])
        XCTAssertEqual(session.keyDown(close).itemToClose, items[0])
        XCTAssertEqual(session.closeCompleted(items[0], succeeded: true), .cancel)
        XCTAssertTrue(session.items.isEmpty)
        XCTAssertFalse(session.presentsPanel)
        XCTAssertEqual(session.refresh(items: items), .cancel)
        XCTAssertEqual(session.modifiersChanged(to: []), .cancel)
    }

    func testAsyncCloseKeepsTheSwitcherOpenAndWaitsForApprovalAcrossControlRelease() throws {
        let context = try makeContext(placement: .current)
        let gate = DeferredDismissal()
        context.browser.family.pageDismissalAuthorizer = gate
        let binding = BrowserShortcut(key: .special(.tab), modifiers: .control)
        let close = BrowserShortcut(key: .character("w"), modifiers: .control)
        var session = try XCTUnwrap(
            RecentTabSwitcherSession(
                direction: .forward, binding: binding, otherBinding: nil, items: context.browser.recentTabItems()))
        XCTAssertNil(session.showDelayElapsed(modifiers: .control))
        let item = try XCTUnwrap(session.keyDown(close).itemToClose)
        var outcome: RecentTabSwitcherSession.Outcome?
        XCTAssertFalse(
            context.action.perform(item, in: BrowserSpaceRuntimeAssignment(space: context.space)) {
                outcome = session.closeCompleted(item, succeeded: $0)
            })
        XCTAssertTrue(session.presentsPanel, "An asynchronous result is not a reason to cancel the switcher")
        XCTAssertNil(session.keyDown(close).itemToClose, "Do not dispatch duplicate closes while waiting")
        XCTAssertNil(session.refresh(items: []), "Do not race the pending close with a list refresh")
        XCTAssertTrue(gate.resolve(true))
        XCTAssertNil(outcome)
        XCTAssertTrue(session.presentsPanel)
        XCTAssertEqual(session.items.count, 1)
        XCTAssertEqual(session.highlightedItem?.focusedTabID, context.shown.id)
        let last = try XCTUnwrap(session.keyDown(close).itemToClose)
        XCTAssertFalse(
            context.action.perform(last, in: BrowserSpaceRuntimeAssignment(space: context.space), clearsSelection: true)
            {
                outcome = session.closeCompleted(last, succeeded: $0)
            })
        XCTAssertNil(session.modifiersChanged(to: []))
        XCTAssertFalse(session.presentsPanel)
        XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
        XCTAssertFalse(gate.resolve(false))
        XCTAssertEqual(outcome, .cancel)
        XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
    }

    func testEscapeAfterImmediateCloseDoesNotRestoreTheClosedTab() throws {
        let context = try makeContext(placement: .current)
        let binding = BrowserShortcut(key: .special(.tab), modifiers: .control)
        var session = try XCTUnwrap(
            RecentTabSwitcherSession(
                direction: .forward, binding: binding, otherBinding: nil, items: context.browser.recentTabItems()))
        XCTAssertNil(session.showDelayElapsed(modifiers: .control))
        let item = try XCTUnwrap(
            session.keyDown(BrowserShortcut(key: .character("w"), modifiers: .control)).itemToClose)
        XCTAssertTrue(context.action.perform(item, in: BrowserSpaceRuntimeAssignment(space: context.space)))
        XCTAssertNil(session.closeCompleted(item, succeeded: true))
        XCTAssertFalse(context.browser.shownSpace?.tabs.contains(context.target.id) == true)
        XCTAssertEqual(session.highlightedItem?.focusedTabID, context.shown.id)
        XCTAssertEqual(
            session.keyDown(BrowserShortcut(key: .special(.escape), modifiers: .control)).outcome, .cancel)
        XCTAssertFalse(context.browser.shownSpace?.tabs.contains(context.target.id) == true)
    }

    // MARK: - Actions - Closing

    func testCloseTargetsTheFocusedSplitMemberAndPreservesDurableTabs() throws {
        for placement: TabPlacement in [.current, .saved, .pinned] {
            let context = try makeContext(placement: placement)
            let expectedTabs = placement.holdsSplits ? [context.target.id, context.companion.id] : [context.target.id]
            XCTAssertEqual(Set(context.item.tabIDs), Set(expectedTabs))
            XCTAssertTrue(
                context.action.perform(context.item, in: BrowserSpaceRuntimeAssignment(space: context.space)))
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

    func testBeforeUnloadCancellationPreservesTheTabAndClosingTheLastItemClearsSelection() throws {
        for placement: TabPlacement in [.current, .saved, .pinned] {
            let context = try makeContext(placement: placement)
            let gate = DeferredDismissal()
            context.browser.family.pageDismissalAuthorizer = gate
            let original = context.browser.sessionSeed
            let assignment = BrowserSpaceRuntimeAssignment(space: context.space)
            var completed = false
            XCTAssertFalse(context.action.perform(context.item, in: assignment) { completed = $0 })
            XCTAssertEqual(gate.assignments.map(\.tabID), [context.target.id])
            XCTAssertFalse(completed)
            XCTAssertFalse(gate.resolve(false))
            XCTAssertEqual(context.browser.sessionSeed, original)
            XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
            XCTAssertFalse(context.action.perform(context.item, in: assignment) { completed = $0 })
            XCTAssertTrue(gate.resolve(true))
            XCTAssertTrue(completed)
            XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
            let last = try XCTUnwrap(context.browser.recentTabItems().first { $0.focusedTabID == context.shown.id })
            XCTAssertFalse(context.action.perform(last, in: assignment, clearsSelection: true))
            XCTAssertFalse(gate.resolve(false))
            XCTAssertEqual(context.browser.shownTab?.id, context.shown.id)
            XCTAssertFalse(context.action.perform(last, in: assignment, clearsSelection: true))
            XCTAssertTrue(gate.resolve(true))
            XCTAssertNil(context.browser.shownTab)
            XCTAssertTrue(context.browser.recentTabItems().isEmpty)
            XCTAssertTrue(context.browser.shownSpace?.tabs.contains(context.companion.id) == true)
            XCTAssertFalse(context.browser.shownSpace?.tabs.contains(context.shown.id) == true)
        }
    }

    func testClosingTheOnlyStartPageLeavesItsWindowWithNoSelection() throws {
        let tab = TabState.Seed.startPage()
        let space = SpaceState.Seed(name: "Test", symbol: "circle", accent: .indigo, folders: [], tabs: [tab])
        let browser = BrowserStore(
            seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tab.id])
        let access = BrowserSpaceAccessController()
        access.attach(browser)
        let action = RecentTabSwitcherCloseAction(browser: browser, spaceAccess: access)
        XCTAssertTrue(
            action.perform(
                try XCTUnwrap(browser.recentTabItems().first), in: BrowserSpaceRuntimeAssignment(space: space),
                clearsSelection: true))
        XCTAssertNil(browser.shownTab)
        XCTAssertEqual(browser.shownSpace?.id, space.id)
        XCTAssertTrue(browser.shownSpace?.tabs.contains(tab.id) == true)
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
    private var completion: (@MainActor (Bool) -> Void)?
    private(set) var assignments: [BrowserTabRuntimeAssignment] = []

    // MARK: - Actions - Dismissal

    func performDismissal(
        of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
        completion: @escaping @MainActor (Bool) -> Void,
        operation: @escaping @MainActor () -> Bool
    ) -> Bool {
        self.assignments = assignments
        self.operation = operation
        self.completion = completion
        return false
    }

    func resolve(_ allowed: Bool) -> Bool {
        let pending = operation
        operation = nil
        let completed = completion
        completion = nil
        let closed = allowed && pending?() == true
        completed?(closed)
        return closed
    }
}
