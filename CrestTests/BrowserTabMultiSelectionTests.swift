import AppKit
import XCTest

@testable import Crest

@MainActor
final class BrowserTabMultiSelectionTests: XCTestCase {
    func testCommandShiftAddsRangeFromCommandClickAndKeepsOtherSelections() {
        let ids = (0..<7).map { _ in TabID() }
        let selection = BrowserTabMultiSelection()
        selection.click(ids[0], units: ids.map { [$0] }, command: true)
        selection.click(ids[3], units: ids.map { [$0] }, command: true)
        selection.click(ids[5], units: ids.map { [$0] }, command: true, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set([ids[0], ids[3], ids[4], ids[5]]))
        XCTAssertEqual(selection.anchorID, ids[3])
        selection.click(ids[4], units: ids.map { [$0] }, command: true, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set([ids[0], ids[3], ids[4]]))
    }

    func testShiftRangeShrinksReversesAndTreatsSplitAsOneUnit() {
        let ids = (0..<6).map { _ in TabID() }
        let units = [[ids[0]], [ids[1], ids[2]], [ids[3]], [ids[4]], [ids[5]]]
        let selection = BrowserTabMultiSelection()
        selection.click(ids[3], units: units)
        selection.click(ids[5], units: units, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set(ids[3...5]))
        selection.click(ids[2], units: units, shift: true)
        XCTAssertEqual(selection.selectedIDs, Set(ids[1...3]))
        selection.click(ids[1], units: units, command: true)
        XCTAssertEqual(selection.selectedIDs, [ids[3]])
    }

    func testHiddenRowsArePrunedAndLostAnchorStartsANewRange() {
        let ids = (0..<4).map { _ in TabID() }
        let selection = BrowserTabMultiSelection()
        selection.click(ids[0], units: ids.map { [$0] }, command: true)
        selection.click(ids[3], units: ids.map { [$0] }, shift: true)
        selection.reconcile(units: [[ids[2]], [ids[3]]])
        XCTAssertEqual(selection.selectedIDs, Set(ids[2...3]))
        XCTAssertNil(selection.anchorID)
        selection.click(ids[2], units: [[ids[2]], [ids[3]]], shift: true)
        XCTAssertEqual(selection.selectedIDs, [ids[2]])
    }

    func testPinCapacityRefusesWholeBatchAndReorderingExistingPinsDoesNotUseExtraSlots() throws {
        var session = makeSession(count: 14)
        for i in 0..<11 { session.spaces[0].tabs[i].placement = .pinned }
        let before = session
        let ids = session.spaces[0].tabs.suffix(3).map(\.id)
        XCTAssertThrowsError(
            try session.applyTabBatch(BrowserTabBatchRequest(ids: ids, in: session.spaces[0]), action: .file(.pinned))
        ) {
            XCTAssertEqual($0 as? BrowserTabBatchError, .pinnedCapacity)
        }
        XCTAssertEqual(session, before)
        let pins = session.spaces[0].pinnedTabs
        _ = try session.applyTabBatch(
            BrowserTabBatchRequest(ids: [pins[2].id, pins[0].id], in: session.spaces[0]),
            action: .file(.pinned, before: pins[5].id))
        XCTAssertEqual(session.spaces[0].pinnedTabs.count, 11)
        let index = try XCTUnwrap(session.spaces[0].tabs.firstIndex { $0.id == pins[5].id })
        XCTAssertEqual(session.spaces[0].tabs[(index - 2)..<index].map(\.id), [pins[2].id, pins[0].id])
    }

    func testWholeSplitMovesToFolderInOrderAndPartialSplitCannotMutate() throws {
        var session = makeSession(count: 5)
        let ids = session.spaces[0].tabs.map(\.id)
        XCTAssertTrue(session.addTabToSplit(ids[2], joining: ids[1], at: nil, in: session.selectedSpaceID))
        let folder = BrowserFolder(title: "Research", location: .current)
        session.spaces[0].folders.append(folder)
        let before = session
        XCTAssertThrowsError(
            try session.applyTabBatch(
                BrowserTabBatchRequest(ids: [ids[1]], in: session.spaces[0]),
                action: .file(.current, folder: folder.id)))
        XCTAssertEqual(session, before)
        let request = BrowserTabBatchRequest(ids: [ids[4], ids[1], ids[2]], in: session.spaces[0])
        _ = try session.applyTabBatch(request, action: .file(.current, folder: folder.id))
        XCTAssertEqual(session.spaces[0].tabs.filter { $0.folderID == folder.id }.map(\.id), request.ids)
        XCTAssertNotNil(session.spaces[0].splitGroup(containing: ids[1]))
        let filed = session
        XCTAssertThrowsError(try session.applyTabBatch(request, action: .file(.pinned)))
        XCTAssertEqual(session, filed)
    }

    func testSavedSplitCopiesLeaveOriginalEntriesAndCapacityFailureMakesNoCopies() throws {
        var session = makeSession(count: 5)
        for i in session.spaces[0].tabs.indices { session.spaces[0].tabs[i].placement = .saved }
        let source = session.spaces[0]
        let ids = source.tabs.map(\.id)
        let before = session
        XCTAssertThrowsError(try session.applyTabBatch(BrowserTabBatchRequest(ids: ids, in: source), action: .split()))
        XCTAssertEqual(session, before)
        let result = try session.applyTabBatch(
            BrowserTabBatchRequest(ids: Array(ids.prefix(3)), in: source), action: .split())
        XCTAssertEqual(result.copies.count, 3)
        XCTAssertEqual(session.spaces[0].savedTabs, source.savedTabs)
        XCTAssertEqual(session.spaces[0].currentTabs.count, 3)
        XCTAssertEqual(Set(session.spaces[0].currentTabs.compactMap(\.splitGroupID)).count, 1)
    }

    func testCrossSpaceMovePreservesOrderAndSelectionUntilFollowIsExplicit() throws {
        var session = makeSession(count: 4)
        let other = BrowserSession.makeBlankSpace(number: 2)
        session.spaces.append(other)
        let source = session.spaces[0]
        let request = BrowserTabBatchRequest(ids: [source.tabs[2].id, source.tabs[0].id], in: source)
        _ = try session.applyTabBatch(
            request, action: .moveToSpace(BrowserSpaceRuntimeAssignment(space: other)),
            fallbackTabID: source.tabs[1].id)
        XCTAssertEqual(session.selectedSpaceID, source.id)
        XCTAssertEqual(session.spaces[1].tabs.suffix(2).map(\.id), request.ids)
        XCTAssertEqual(session.spaces[1].selectedTabID, other.selectedTabID)
        XCTAssertEqual(session.spaces[0].selectedTabID, source.tabs[1].id)
    }

    func testMixedArchiveRefusalAndStaleRequestNeverPublishPartialChanges() throws {
        var session = makeSession(count: 3)
        session.spaces[0].tabs[1].placement = .saved
        let request = BrowserTabBatchRequest(ids: session.spaces[0].tabs.map(\.id), in: session.spaces[0])
        let before = session
        XCTAssertThrowsError(try session.applyTabBatch(request, action: .close))
        XCTAssertEqual(session, before)
        session.spaces[0].tabs.removeLast()
        let changed = session
        XCTAssertThrowsError(try session.applyTabBatch(request, action: .delete))
        XCTAssertEqual(session, changed)
    }

    func testDuplicateOrderAndArchiveFallbackAreStable() throws {
        var session = makeSession(count: 4)
        let source = session.spaces[0]
        let ids = [source.tabs[2].id, source.tabs[0].id]
        let result = try session.applyTabBatch(BrowserTabBatchRequest(ids: ids, in: source), action: .duplicate)
        XCTAssertEqual(session.spaces[0].tabs.suffix(2).map(\.id), result.copies.map(\.copy))
        XCTAssertEqual(session.spaces[0].selectedTabID, source.selectedTabID)
        _ = try session.applyTabBatch(
            BrowserTabBatchRequest(ids: ids, in: session.spaces[0]), action: .close,
            fallbackTabID: source.tabs[1].id)
        XCTAssertEqual(session.spaces[0].archivedTabs.count, 2)
        XCTAssertEqual(session.spaces[0].selectedTabID, source.tabs[1].id)
    }

    func testBatchAuthorizationRejectsLockedDestinationChangedProfileAndInactiveSource() throws {
        var session = makeSession(count: 3)
        session.spaces.append(BrowserSession.makeBlankSpace(number: 2))
        let source = session.spaces[0]
        let destination = session.spaces[1]
        let request = BrowserTabBatchRequest(ids: source.tabs.map(\.id), in: source)
        let browser = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let actions = BrowserTabBatchActions(browser: browser, spaceAccess: BrowserSpaceAccessController())
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: destination.id)
        var before = browser.session
        XCTAssertFalse(
            actions.perform(request, action: .moveToSpace(BrowserSpaceRuntimeAssignment(space: destination))))
        XCTAssertEqual(browser.session, before)
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: source.id)
        before = browser.session
        XCTAssertFalse(actions.perform(request, action: .delete))
        XCTAssertEqual(browser.session, before)
        browser.session = session
        browser.selectSpace(destination.id)
        before = browser.session
        XCTAssertFalse(actions.perform(request, action: .delete))
        XCTAssertEqual(browser.session, before)
        browser.session = session
        browser.session.spaces[0] = BrowserSpace(
            id: source.id, profile: BrowsingProfile(), name: source.name, symbol: source.symbol,
            accent: source.accent, folders: source.folders, tabs: source.tabs, selectedTabID: source.selectedTabID)
        before = browser.session
        XCTAssertFalse(actions.perform(request, action: .delete))
        XCTAssertEqual(browser.session, before)
    }

    func testBatchFollowActivatesExactlyOneTabAndPersistsOnceInEitherBrowsingMode() throws {
        for mode in [BrowserBrowsingMode.standard, .privateBrowsing] {
            for follows in [false, true] {
                var session = makeSession(count: 3)
                session.spaces.append(BrowserSession.makeBlankSpace(number: 2))
                let source = session.spaces[0]
                let destination = session.spaces[1]
                let persistence = InMemoryBrowserSessionPersistence()
                let preferences = BrowserLinkPreferenceStore(persistence: InMemoryBrowserLinkPreferencesPersistence())
                preferences.followsTabsMovedToAnotherSpace = follows
                let browser = BrowserStore(
                    session: session, persistence: persistence, browsingMode: mode, linkPreferences: preferences)
                let initialSaves = persistence.savedScopes.count
                let ids = [source.tabs[2].id, source.tabs[0].id]
                try browser.commitTabBatch(
                    BrowserTabBatchRequest(ids: ids, in: source),
                    action: .moveToSpace(BrowserSpaceRuntimeAssignment(space: destination)))
                XCTAssertEqual(browser.session.spaces[1].tabs.suffix(2).map(\.id), ids)
                XCTAssertEqual(browser.session.selectedSpaceID, follows ? destination.id : source.id)
                XCTAssertEqual(
                    browser.session.spaces[1].selectedTabID, follows ? source.selectedTabID : destination.selectedTabID)
                XCTAssertEqual(browser.consumeMovedTabActivation(), follows)
                XCTAssertFalse(browser.consumeMovedTabActivation())
                XCTAssertEqual(persistence.savedScopes.count, initialSaves + 1)
                XCTAssertEqual(browser.isPrivateBrowsing, mode.isPrivate)
            }
        }
    }

    func testDuplicatingWholeSplitKeepsOriginalPageActiveAndCopyGrouped() throws {
        var session = makeSession(count: 4)
        let ids = session.spaces[0].tabs.map(\.id)
        XCTAssertTrue(session.addTabToSplit(ids[2], joining: ids[1], at: nil, in: session.selectedSpaceID))
        session.spaces[0].selectedTabID = ids[0]
        let result = try session.applyTabBatch(
            BrowserTabBatchRequest(ids: [ids[1], ids[2]], in: session.spaces[0]), action: .duplicate)
        XCTAssertEqual(session.spaces[0].selectedTabID, ids[0])
        let group = try XCTUnwrap(session.spaces[0].splitGroup(containing: result.copies[0].copy))
        XCTAssertEqual(session.spaces[0].splitGroupMembers(of: group).map(\.id), result.copies.map(\.copy))
    }

    func testMissingMemberAtCaptureRefusesEntireBatch() {
        var session = makeSession(count: 2)
        let before = session
        let request = BrowserTabBatchRequest(ids: [session.spaces[0].tabs[0].id, TabID()], in: session.spaces[0])
        XCTAssertThrowsError(try session.applyTabBatch(request, action: .delete))
        XCTAssertEqual(session, before)
    }

    func testDragCarriesCapturedBatchAndCancellationRestoresEveryLiftedRow() {
        let session = makeSession(count: 3)
        let source = session.spaces[0]
        let ids = [source.tabs[0].id, source.tabs[2].id]
        let request = BrowserTabBatchRequest(ids: ids, in: source)
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(
                tabID: ids[0], spaceID: source.id, profileID: source.profile.id)
        ).selecting(request)
        let browser = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let state = browser.sidebarReorderState
        state.begin(item: item, section: .tabs(placement: .current, folderID: nil), at: .zero)
        XCTAssertTrue(state.isLifted(.tab(ids[0])))
        XCTAssertTrue(state.isLifted(.tab(ids[1])))
        state.cancel()
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertFalse(state.isLifted(.tab(ids[1])))
        XCTAssertEqual(browser.session, session)
        let forbidden = BrowserSidebarReorderTarget(
            kind: .insert(
                section: .tabs(placement: .pinned, folderID: nil), beforeID: nil, index: 0))
        let commit = BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController())
        XCTAssertFalse(commit.apply(forbidden, for: item))
        XCTAssertEqual(browser.session, session)
        let target = BrowserSidebarReorderTarget(
            kind: .insert(
                section: .tabs(placement: .saved, folderID: nil), beforeID: nil, index: 0))
        browser.tabMultiSelection.selectAll(units: [[source.tabs[1].id]])
        XCTAssertTrue(commit.apply(target, for: item))
        XCTAssertEqual(browser.selectedSpace?.savedTabs.map(\.id), ids)
        XCTAssertEqual(browser.selectedSpace?.currentTabs.map(\.id), [source.tabs[1].id])
        let before = browser.session
        XCTAssertFalse(commit.apply(target, for: item))
        XCTAssertEqual(browser.session, before)
    }

    func testMixedDragExcludesPinsAndPinOnlyDragStaysWithinItsSpace() throws {
        var session = makeSession(count: 4)
        session.spaces[0].tabs[0].placement = .pinned
        session.spaces[0].tabs[1].placement = .pinned
        let source = session.spaces[0]
        let ids = source.tabs.map(\.id)
        let selection = BrowserTabMultiSelection()
        selection.selectAll(units: ids.map { [$0] })
        let mixed = BrowserTabBatchRequest(ids: ids, in: source)
        let filtered = selection.prepareForDrag(mixed, in: source)
        XCTAssertEqual(filtered.ids, Array(ids.suffix(2)))
        XCTAssertEqual(selection.selectedIDs, Set(ids.suffix(2)))
        XCTAssertEqual(selection.rejectedPinnedIDs, Set(ids.prefix(2)))
        let browser = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let commit = BrowserSidebarReorderCommit(browser: browser, spaceAccess: BrowserSpaceAccessController())
        let pins = BrowserTabBatchRequest(ids: Array(ids.prefix(2)), in: source)
        let item = BrowserSidebarReorderItem.tab(
            BrowserTabDragItem(tabID: ids[0], spaceID: source.id, profileID: source.profile.id)
        ).selecting(pins)
        XCTAssertNotNil(
            commit.batchReason(
                BrowserSidebarReorderTarget(kind: .splitInsert(assignment: pins.assignment, index: 0)), request: pins))
        XCTAssertTrue(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .insert(section: .tabs(placement: .pinned, folderID: nil), beforeID: nil, index: 0)),
                for: item))
        XCTAssertTrue(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .insert(section: .tabs(placement: .saved, folderID: nil), beforeID: nil, index: 0)), for: item
            ))
        XCTAssertEqual(browser.selectedSpace?.savedTabs.map(\.id), pins.ids)
    }

    func testBatchLayoutClosesOnlySelectedIntervalsAndReservesTheirCombinedHeight() {
        let ids = (0..<4).map { _ in BrowserSidebarReorderItemID.tab(TabID()) }
        var layout = BrowserSidebarReorderLayout(
            sourceID: ids[0], sourceFrame: CGRect(x: 0, y: 0, width: 220, height: 40), hiddenIDs: [ids[0], ids[2]])
        layout.removedFrames = [
            CGRect(x: 0, y: 0, width: 220, height: 40), CGRect(x: 0, y: 80, width: 220, height: 40),
        ]
        layout.batchHeight = 80
        let assignment = BrowserSpaceRuntimeAssignment(spaceID: SpaceID(), profileID: UUID())
        let row = BrowserSidebarReorderRow(
            id: ids[3], space: assignment, section: .tabs(placement: .current, folderID: nil),
            frame: CGRect(x: 0, y: 120, width: 220, height: 40))
        XCTAssertEqual(layout.frame(for: row)?.minY, 40)
        XCTAssertEqual(layout.gapHeight, 80)
    }

    func testPointerTargetsAndRangesFollowLiveRowsAfterMovingAndReparenting() throws {
        let session = makeSession(count: 3)
        let browser = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let space = try XCTUnwrap(browser.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 200, width: 400, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let content = try XCTUnwrap(window.contentView)
        let container = NSView(frame: NSRect(x: 20, y: 80, width: 240, height: 400))
        content.addSubview(container)
        let rows = space.tabs.enumerated().map { index, tab in
            let row = BrowserNativeTabSelectionTarget.TargetView(
                frame: NSRect(x: 0, y: 300 - index * 40, width: 220, height: 40))
            row.browser = browser
            row.assignment = assignment
            row.tabID = tab.id
            container.addSubview(row)
            return row
        }
        func target(_ row: NSView) -> TabID? {
            BrowserNativeTabSelectionTarget.TargetView.tab(
                at: row.convert(NSPoint(x: 100, y: 20), to: nil), in: window,
                browser: browser, assignment: assignment)
        }
        XCTAssertEqual(target(rows[0]), space.tabs[0].id)
        // Reordering must take effect without registering another drag frame.
        rows[0].setFrameOrigin(NSPoint(x: 0, y: 180))
        XCTAssertEqual(target(rows[0]), space.tabs[0].id)
        XCTAssertEqual(target(rows[1]), space.tabs[1].id)
        XCTAssertEqual(
            BrowserSidebarSelection.units(in: browser).flatMap { $0 },
            [
                space.tabs[1].id, space.tabs[2].id, space.tabs[0].id,
            ])
        // Move a row across sections and translate the entire sidebar.
        content.addSubview(rows[0])
        rows[0].setFrameOrigin(NSPoint(x: 30, y: 500))
        container.setFrameOrigin(NSPoint(x: 40, y: 100))
        XCTAssertEqual(target(rows[0]), space.tabs[0].id)
        XCTAssertEqual(target(rows[2]), space.tabs[2].id)
        XCTAssertEqual(BrowserSidebarSelection.units(in: browser).first, [space.tabs[0].id])
        container.isHidden = true
        XCTAssertNil(target(rows[2]))
        rows[0].removeFromSuperview()
        XCTAssertNil(
            BrowserNativeTabSelectionTarget.TargetView.tab(
                at: NSPoint(x: 130, y: 520), in: window, browser: browser, assignment: assignment))
    }

    func testSelectedNestedFolderMovesOutWithItsSubtreeAndLooseTabsInOrder() throws {
        var session = makeSession(count: 4)
        let spaceID = session.selectedSpaceID
        let parent = try XCTUnwrap(session.addFolder(title: "Parent", in: spaceID))
        let child = try XCTUnwrap(session.addFolder(title: "Child", parentID: parent, in: spaceID))
        let grandchild = try XCTUnwrap(session.addFolder(title: "Grandchild", parentID: child, in: spaceID))
        let ids = session.spaces[0].tabs.map(\.id)
        XCTAssertTrue(session.fileTabs([ids[0]], in: spaceID, into: child, location: .saved))
        XCTAssertTrue(session.fileTabs([ids[1]], in: spaceID, into: grandchild, location: .saved))
        let request = BrowserTabBatchRequest(items: [.folder(child), .tab(ids[2])], in: session.spaces[0])
        _ = try session.applyTabBatch(request, action: .file(.current, before: ids[3]))
        let moved = session.spaces[0]
        XCTAssertNil(moved.folders.first { $0.id == child }?.parentID)
        XCTAssertEqual(moved.folders.first { $0.id == grandchild }?.parentID, child)
        XCTAssertEqual(moved.folders.first { $0.id == child }?.location, .current)
        XCTAssertEqual(moved.tabs.first { $0.id == ids[0] }?.folderID, child)
        XCTAssertEqual(moved.tabs.first { $0.id == ids[1] }?.folderID, grandchild)
        XCTAssertEqual(moved.currentTabs.map(\.id), ids)
        XCTAssertTrue(moved.folderTree.isValid)
        XCTAssertNotNil(moved.folders.first { $0.id == parent })
    }

    func testSelectedAncestorCarriesDescendantsOnlyOnceAndEmptyFoldersRemainMovable() throws {
        var session = makeSession(count: 1)
        let spaceID = session.selectedSpaceID
        let parent = try XCTUnwrap(session.addFolder(title: "Parent", in: spaceID))
        let child = try XCTUnwrap(session.addFolder(title: "Empty child", parentID: parent, in: spaceID))
        let request = BrowserTabBatchRequest(items: [.folder(parent), .folder(child)], in: session.spaces[0])
        XCTAssertEqual(request.rootItems, [.folder(parent)])
        XCTAssertTrue(request.ids.isEmpty)
        _ = try session.applyTabBatch(request, action: .file(.current))
        XCTAssertEqual(session.spaces[0].folders.first { $0.id == child }?.parentID, parent)
        XCTAssertTrue(session.spaces[0].folders.allSatisfy { $0.location == .current })
    }

    func testFolderBatchRejectsCyclesAndChangedSubtreesWithoutPartialMoves() throws {
        var session = makeSession(count: 2)
        let spaceID = session.selectedSpaceID
        let parent = try XCTUnwrap(session.addFolder(title: "Parent", in: spaceID))
        let child = try XCTUnwrap(session.addFolder(title: "Child", parentID: parent, in: spaceID))
        let request = BrowserTabBatchRequest(
            items: [.tab(session.spaces[0].tabs[0].id), .folder(parent)], in: session.spaces[0])
        let before = session
        XCTAssertThrowsError(try session.applyTabBatch(request, action: .file(.saved, folder: child)))
        XCTAssertEqual(session, before)
        _ = session.addFolder(title: "New descendant", parentID: child, in: spaceID)
        let changed = session
        XCTAssertThrowsError(try session.applyTabBatch(request, action: .file(.current)))
        XCTAssertEqual(session, changed)
    }

    func testFolderAndWholeSplitCanBeWrappedWithoutFlatteningAndPinsAreExcluded() throws {
        var session = makeSession(count: 4)
        let spaceID = session.selectedSpaceID
        let ids = session.spaces[0].tabs.map(\.id)
        let folder = try XCTUnwrap(session.addFolder(title: "Empty", in: spaceID))
        XCTAssertTrue(session.addTabToSplit(ids[0], joining: ids[1], at: nil, in: spaceID))
        XCTAssertTrue(session.moveTab(ids[3], to: .pinned))
        let items: [BrowserSelectionItemID] = [.folder(folder), .tab(ids[0]), .tab(ids[1]), .tab(ids[3])]
        let selection = BrowserTabMultiSelection()
        selection.selectAll(units: items.map { [$0] })
        let captured = BrowserTabBatchRequest(items: items, in: session.spaces[0])
        let request = selection.prepareForDrag(captured, in: session.spaces[0])
        XCTAssertFalse(request.ids.contains(ids[3]))
        XCTAssertTrue(selection.contains(.folder(folder)))
        _ = try session.applyTabBatch(request, action: .newFolder(.saved))
        let result = session.spaces[0]
        let wrapper = try XCTUnwrap(result.folders.first { $0.id == folder }?.parentID)
        XCTAssertEqual(result.tabs.first { $0.id == ids[0] }?.folderID, wrapper)
        XCTAssertEqual(result.tabs.first { $0.id == ids[1] }?.folderID, wrapper)
        XCTAssertEqual(
            result.tabs.first { $0.id == ids[0] }?.splitGroupID, result.tabs.first { $0.id == ids[1] }?.splitGroupID)
        XCTAssertEqual(result.pinnedTabs.map(\.id), [ids[3]])
        XCTAssertTrue(result.folderTree.isValid)
    }

    private func makeSession(count: Int) -> BrowserSession {
        var space = BrowserSession.makeBlankSpace(number: 1)
        space.tabs = (0..<count).map { index in
            BrowserTab(
                title: "Tab \(index)", url: URL(string: "https://example.com/\(index)"), symbol: "globe",
                placement: .current)
        }
        space.selectedTabID = space.tabs.first?.id
        return BrowserSession(spaces: [space], selectedSpaceID: space.id)
    }
}
