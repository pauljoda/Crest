import AppKit
import Observation
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
            try applyBatch(
                BrowserTabBatchRequest(ids: ids, in: session.spaces[0]), action: .file(.pinned), to: &session)
        ) {
            XCTAssertEqual($0 as? BrowserTabBatchError, .pinnedCapacity)
        }
        XCTAssertEqual(session, before)
        let pins = session.spaces[0].pinnedTabs
        _ = try applyBatch(
            BrowserTabBatchRequest(ids: [pins[2].id, pins[0].id], in: session.spaces[0]),
            action: .file(.pinned, before: pins[5].id), to: &session)
        XCTAssertEqual(session.spaces[0].pinnedTabs.count, 11)
        let index = try XCTUnwrap(session.spaces[0].tabs.firstIndex { $0.id == pins[5].id })
        XCTAssertEqual(session.spaces[0].tabs[(index - 2)..<index].map(\.id), [pins[2].id, pins[0].id])
    }

    func testWholeSplitMovesToFolderInOrderAndPartialSplitCannotMutate() throws {
        var session = makeSession(count: 5)
        let ids = session.spaces[0].tabs.map(\.id)
        session = try organized(session) { browser, space in
            XCTAssertTrue(browser.addTabToSplit(dragItem(ids[2], in: space), joining: ids[1], at: nil))
        }
        let folder = BrowserFolder(title: "Research", location: .current)
        session.spaces[0].folders.append(folder)
        let before = session
        XCTAssertThrowsError(
            try applyBatch(
                BrowserTabBatchRequest(ids: [ids[1]], in: session.spaces[0]),
                action: .file(.current, folder: folder.id), to: &session))
        XCTAssertEqual(session, before)
        let request = BrowserTabBatchRequest(ids: [ids[4], ids[1], ids[2]], in: session.spaces[0])
        _ = try applyBatch(request, action: .file(.current, folder: folder.id), to: &session)
        XCTAssertEqual(session.spaces[0].tabs.filter { $0.folderID == folder.id }.map(\.id), request.ids)
        XCTAssertNotNil(session.spaces[0].splitGroup(containing: ids[1]))
        let filed = session
        XCTAssertThrowsError(try applyBatch(request, action: .file(.pinned), to: &session))
        XCTAssertEqual(session, filed)
    }

    func testSavedSplitCopiesLeaveOriginalEntriesAndCapacityFailureMakesNoCopies() throws {
        var session = makeSession(count: 5)
        for i in session.spaces[0].tabs.indices { session.spaces[0].tabs[i].placement = .saved }
        let source = session.spaces[0]
        let ids = source.tabs.map(\.id)
        let before = session
        XCTAssertThrowsError(
            try applyBatch(BrowserTabBatchRequest(ids: ids, in: source), action: .split(), to: &session))
        XCTAssertEqual(session, before)
        let result = try applyBatch(
            BrowserTabBatchRequest(ids: Array(ids.prefix(3)), in: source), action: .split(), to: &session)
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
        let browser = makeBatchStore(
            session, showing: [source.id: source.tabs[0].id, other.id: other.tabs[0].id],
            fallbackTabID: source.tabs[1].id)
        try browser.commitTabBatch(request, action: .moveToSpace(BrowserSpaceRuntimeAssignment(space: other)))
        XCTAssertEqual(browser.selectedSpaceID, source.id)
        XCTAssertEqual(browser.session.spaces[1].tabs.suffix(2).map(\.id), request.ids)
        XCTAssertEqual(browser.selectedTabID(in: other.id), other.tabs[0].id)
        XCTAssertEqual(browser.selectedTabID(in: source.id), source.tabs[1].id)
    }

    func testMixedArchiveRefusalAndStaleRequestNeverPublishPartialChanges() throws {
        var session = makeSession(count: 3)
        session.spaces[0].tabs[1].placement = .saved
        let request = BrowserTabBatchRequest(ids: session.spaces[0].tabs.map(\.id), in: session.spaces[0])
        let before = session
        XCTAssertThrowsError(try applyBatch(request, action: .close, to: &session))
        XCTAssertEqual(session, before)
        session.spaces[0].tabs.removeLast()
        let changed = session
        XCTAssertThrowsError(try applyBatch(request, action: .delete, to: &session))
        XCTAssertEqual(session, changed)
    }

    func testDuplicateOrderAndArchiveFallbackAreStable() throws {
        let session = makeSession(count: 4)
        let source = session.spaces[0]
        let ids = [source.tabs[2].id, source.tabs[0].id]
        let browser = makeBatchStore(session, showing: [source.id: source.tabs[0].id], fallbackTabID: source.tabs[1].id)
        try browser.commitTabBatch(BrowserTabBatchRequest(ids: ids, in: source), action: .duplicate)
        let copies = Array(try XCTUnwrap(browser.session.space(id: source.id)).tabs.suffix(2))
        XCTAssertEqual(copies.map(\.title), [source.tabs[2].title, source.tabs[0].title])
        XCTAssertTrue(Set(copies.map(\.id)).isDisjoint(with: source.tabs.map(\.id)))
        XCTAssertEqual(browser.selectedTabID(in: source.id), source.tabs[0].id)
        try browser.commitTabBatch(
            BrowserTabBatchRequest(ids: ids, in: try XCTUnwrap(browser.session.space(id: source.id))), action: .close)
        XCTAssertEqual(browser.session.space(id: source.id)?.archivedTabs.count, 2)
        XCTAssertEqual(browser.selectedTabID(in: source.id), source.tabs[1].id)
    }

    func testBatchAuthorizationRejectsLockedDestinationChangedProfileAndInactiveSource() throws {
        var session = makeSession(count: 3)
        session.spaces.append(BrowserSession.makeBlankSpace(number: 2))
        let source = session.spaces[0]
        let destination = session.spaces[1]
        let request = BrowserTabBatchRequest(ids: source.tabs.map(\.id), in: source)
        let browser = BrowserStore(session: session)
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
        browser.selectSpace(source.id)
        browser.session.spaces[0] = BrowserSpace(
            id: source.id, profile: BrowsingProfile(), name: source.name, symbol: source.symbol,
            accent: source.accent, folders: source.folders, tabs: source.tabs)
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
                let preferences = BrowserLinkPreferenceStore(persistence: InMemoryBrowserLinkPreferencesPersistence())
                preferences.followsTabsMovedToAnotherSpace = follows
                let browser = BrowserStore(
                    session: session,
                    showing: source.id, tabs: [source.id: source.tabs[0].id, destination.id: destination.tabs[0].id],
                    browsingMode: mode, linkPreferences: preferences)
                let initialRevision = browser.family.syncRevision
                let ids = [source.tabs[2].id, source.tabs[0].id]
                let actions = BrowserTabBatchActions(browser: browser, spaceAccess: BrowserSpaceAccessController())
                XCTAssertTrue(
                    actions.perform(
                        BrowserTabBatchRequest(ids: ids, in: source),
                        action: .moveToSpace(BrowserSpaceRuntimeAssignment(space: destination))))
                XCTAssertEqual(browser.session.spaces[1].tabs.suffix(2).map(\.id), ids)
                XCTAssertEqual(browser.selectedSpaceID, follows ? destination.id : source.id)
                XCTAssertEqual(
                    browser.selectedTabID(in: destination.id), follows ? source.tabs[0].id : destination.tabs[0].id)
                XCTAssertEqual(browser.consumeMovedTabActivation(), follows)
                XCTAssertFalse(browser.consumeMovedTabActivation())
                XCTAssertEqual(browser.family.syncRevision, initialRevision.successor())
                XCTAssertEqual(browser.isPrivateBrowsing, mode.isPrivate)
            }
        }
    }

    func testDuplicatingWholeSplitKeepsOriginalPageActiveAndCopyGrouped() throws {
        var session = makeSession(count: 4)
        let ids = session.spaces[0].tabs.map(\.id)
        session = try organized(session) { browser, space in
            XCTAssertTrue(browser.addTabToSplit(dragItem(ids[2], in: space), joining: ids[1], at: nil))
        }
        let spaceID = session.spaces[0].id
        let browser = makeBatchStore(session, showing: [spaceID: ids[0]])
        try browser.commitTabBatch(
            BrowserTabBatchRequest(ids: [ids[1], ids[2]], in: session.spaces[0]), action: .duplicate)
        XCTAssertEqual(browser.selectedTabID(in: spaceID), ids[0])
        let space = try XCTUnwrap(browser.session.space(id: spaceID))
        let copies = space.tabs.filter { !ids.contains($0.id) }.map(\.id)
        XCTAssertEqual(copies.count, 2)
        let group = try XCTUnwrap(space.splitGroup(containing: copies[0]))
        XCTAssertNotEqual(group, space.splitGroup(containing: ids[1]))
        XCTAssertEqual(space.splitGroupMembers(of: group).map(\.id), copies)
    }

    func testBatchDismissalDefersAllChangesAndRevalidatesAfterNativeConfirmation() throws {
        final class DeferredDismissal: BrowserPageDismissalAuthorizing {
            var assignments: [BrowserTabRuntimeAssignment] = []
            var operation: (@MainActor () -> Bool)?
            func performDismissal(of assignments: [BrowserTabRuntimeAssignment], in browser: BrowserStore,
                operation: @escaping @MainActor () -> Bool) -> Bool {
                self.assignments = assignments; self.operation = operation; return false
            }
        }
        let session = makeSession(count: 3), source = session.spaces[0]
        let browser = BrowserStore(session: session)
        let gate = DeferredDismissal(); browser.family.pageDismissalAuthorizer = gate
        let actions = BrowserTabBatchActions(browser: browser, spaceAccess: BrowserSpaceAccessController())
        let request = BrowserTabBatchRequest(ids: Array(source.tabs.prefix(2).map(\.id)), in: source)
        XCTAssertFalse(actions.perform(request, action: .close))
        XCTAssertEqual(gate.assignments.map(\.tabID), request.ids)
        XCTAssertEqual(browser.session, session)
        gate.operation = nil // Native cancellation never commits a subset.
        XCTAssertEqual(browser.session, session)
        XCTAssertFalse(actions.perform(request, action: .close))
        browser.session.spaces[0].tabs[0].placement = .saved
        let changed = browser.session
        XCTAssertFalse(try XCTUnwrap(gate.operation)())
        XCTAssertEqual(browser.session, changed)
        browser.session = session
        XCTAssertFalse(actions.perform(request, action: .close))
        XCTAssertTrue(try XCTUnwrap(gate.operation)())
        XCTAssertEqual(browser.session.spaces[0].archivedTabs.count, 2)
        XCTAssertEqual(browser.session.spaces[0].tabs.map(\.id), [source.tabs[2].id])
    }

    func testMissingMemberAtCaptureRefusesEntireBatch() {
        var session = makeSession(count: 2)
        let before = session
        let request = BrowserTabBatchRequest(ids: [session.spaces[0].tabs[0].id, TabID()], in: session.spaces[0])
        XCTAssertThrowsError(try applyBatch(request, action: .delete, to: &session))
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
        let browser = BrowserStore(session: session)
        let sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        let state = sidebarInteraction.sidebarReorderState
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
        let browser = BrowserStore(session: session)
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

    func testUnmountingScrollRowsPreservesLogicalSelectionUntilTabsAreRemoved() async throws {
        let session = makeSession(count: 3)
        let browser = BrowserStore(session: session)
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let reorder = interaction.sidebarReorderState
        let space = session.spaces[0]
        let ids = space.tabs.map(\.id)
        let region = UUID()
        for (index, tab) in space.tabs.enumerated() {
            reorder.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id), space: BrowserSpaceRuntimeAssignment(space: space),
                    section: .tabs(placement: tab.placement, folderID: nil),
                    frame: CGRect(x: 0, y: index * 40, width: 200, height: 40)),
                owner: UUID(), scrollRegionID: index == 0 ? nil : region)
        }
        browser.tabMultiSelection.selectAll(units: BrowserSidebarSelection.itemUnits(in: browser, reorder: reorder))
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
        let reconciled = expectation(description: "Selection reconciles independently of mounted rows")
        withObservationTracking {
            _ = reorder.selectionRowsRevision
        } onChange: {
            Task { @MainActor in
                browser.tabMultiSelection.reconcile(
                    units: BrowserSidebarSelection.itemUnits(in: browser, reorder: reorder))
                reconciled.fulfill()
            }
        }

        reorder.removeScrollRegion(for: region)
        await fulfillment(of: [reconciled], timeout: 1)

        // Unmounting scroll content is not a model removal: lazy rows remain selectable.
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
        XCTAssertEqual(browser.session, session)
        browser.closeTab(ids[2], matching: BrowserSpaceRuntimeAssignment(space: space))
        browser.tabMultiSelection.reconcile(units: BrowserSidebarSelection.itemUnits(in: browser, reorder: reorder))
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids.prefix(2)))
    }

    func testSelectedNestedFolderMovesOutWithItsSubtreeAndLooseTabsInOrder() throws {
        var session = makeSession(count: 4)
        let ids = session.spaces[0].tabs.map(\.id)
        var folders: [FolderID] = []
        session = try organized(session) { browser, space in
            let assignment = BrowserSpaceRuntimeAssignment(space: space)
            let parent = try XCTUnwrap(browser.addFolder(title: "Parent", in: space.id))
            let child = try XCTUnwrap(browser.addFolder(title: "Child", parentID: parent, in: space.id))
            let grandchild = try XCTUnwrap(browser.addFolder(title: "Grandchild", parentID: child, in: space.id))
            XCTAssertTrue(browser.fileTabs([ids[0]], matching: assignment, into: child, location: .saved))
            XCTAssertTrue(browser.fileTabs([ids[1]], matching: assignment, into: grandchild, location: .saved))
            folders = [parent, child, grandchild]
        }
        let (parent, child, grandchild) = (folders[0], folders[1], folders[2])
        let request = BrowserTabBatchRequest(items: [.folder(child), .tab(ids[2])], in: session.spaces[0])
        _ = try applyBatch(request, action: .file(.current, before: ids[3]), to: &session)
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
        let parent = FolderID(), child = FolderID()
        session.spaces[0].folders = [
            BrowserFolder(id: parent, title: "Parent"), BrowserFolder(id: child, title: "Empty child", parentID: parent),
        ]
        let request = BrowserTabBatchRequest(items: [.folder(parent), .folder(child)], in: session.spaces[0])
        XCTAssertEqual(request.rootItems, [.folder(parent)])
        XCTAssertTrue(request.ids.isEmpty)
        _ = try applyBatch(request, action: .file(.current), to: &session)
        XCTAssertEqual(session.spaces[0].folders.first { $0.id == child }?.parentID, parent)
        XCTAssertTrue(session.spaces[0].folders.allSatisfy { $0.location == .current })
    }

    func testFolderBatchRejectsCyclesAndChangedSubtreesWithoutPartialMoves() throws {
        var session = makeSession(count: 2)
        let parent = FolderID(), child = FolderID()
        session.spaces[0].folders = [
            BrowserFolder(id: parent, title: "Parent"), BrowserFolder(id: child, title: "Child", parentID: parent),
        ]
        let request = BrowserTabBatchRequest(
            items: [.tab(session.spaces[0].tabs[0].id), .folder(parent)], in: session.spaces[0])
        let before = session
        XCTAssertThrowsError(try applyBatch(request, action: .file(.saved, folder: child), to: &session))
        XCTAssertEqual(session, before)
        session.spaces[0].folders.append(BrowserFolder(title: "New descendant", parentID: child))
        let changed = session
        XCTAssertThrowsError(try applyBatch(request, action: .file(.current), to: &session))
        XCTAssertEqual(session, changed)
    }

    func testFolderAndWholeSplitCanBeWrappedWithoutFlatteningAndPinsAreExcluded() throws {
        var session = makeSession(count: 4)
        let ids = session.spaces[0].tabs.map(\.id)
        var created: FolderID?
        session = try organized(session) { browser, space in
            created = browser.addFolder(title: "Empty", in: space.id)
            XCTAssertTrue(browser.addTabToSplit(dragItem(ids[0], in: space), joining: ids[1], at: nil))
            XCTAssertTrue(browser.moveTab(ids[3], to: .pinned))
        }
        let folder = try XCTUnwrap(created)
        let items: [BrowserSelectionItemID] = [.folder(folder), .tab(ids[0]), .tab(ids[1]), .tab(ids[3])]
        let selection = BrowserTabMultiSelection()
        selection.selectAll(units: items.map { [$0] })
        let captured = BrowserTabBatchRequest(items: items, in: session.spaces[0])
        let request = selection.prepareForDrag(captured, in: session.spaces[0])
        XCTAssertFalse(request.ids.contains(ids[3]))
        XCTAssertTrue(selection.contains(.folder(folder)))
        _ = try applyBatch(request, action: .newFolder(.saved), to: &session)
        let result = session.spaces[0]
        let wrapper = try XCTUnwrap(result.folders.first { $0.id == folder }?.parentID)
        XCTAssertEqual(result.tabs.first { $0.id == ids[0] }?.folderID, wrapper)
        XCTAssertEqual(result.tabs.first { $0.id == ids[1] }?.folderID, wrapper)
        XCTAssertEqual(
            result.tabs.first { $0.id == ids[0] }?.splitGroupID, result.tabs.first { $0.id == ids[1] }?.splitGroupID)
        XCTAssertEqual(result.pinnedTabs.map(\.id), [ids[3]])
        XCTAssertTrue(result.folderTree.isValid)
    }

    func testFortyTabRangeIncludesUnrealizedFolderRowsWithSixteenOrNoTargets() throws {
        var session = makeSession(count: 40)
        let folder = BrowserFolder(title: "Long folder", location: .current)
        session.spaces[0].folders = [folder]
        for index in session.spaces[0].tabs.indices { session.spaces[0].tabs[index].folderID = folder.id }
        let browser = BrowserStore(session: session)
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let space = try XCTUnwrap(browser.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let ids = space.tabs.map(\.id)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 640),
            styleMask: [.borderless], backing: .buffered, defer: false)
        let targets = ids.prefix(16).enumerated().map { index, id in
            let target = BrowserNativeTabSelectionTarget.TargetView(
                frame: NSRect(x: 0, y: index * 40, width: 280, height: 40))
            target.browser = browser
            target.assignment = assignment
            target.tabID = id
            window.contentView?.addSubview(target)
            return target
        }
        for mounted in [true, false] {
            if !mounted {
                for target in targets { target.removeFromSuperview() }
            }
            let units = BrowserSidebarSelection.itemUnits(in: browser, reorder: interaction.sidebarReorderState)
            browser.tabMultiSelection.click(ids[0], units: units)
            browser.tabMultiSelection.click(ids[39], units: units, shift: true)
            XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
            XCTAssertEqual(
                BrowserSidebarSelection.request(
                    for: ids[0], browser: browser,
                    reorder: interaction.sidebarReorderState)?.ids, ids)
        }
        browser.tabMultiSelection.selectAll(
            units: BrowserSidebarSelection.itemUnits(
                in: browser, reorder: interaction.sidebarReorderState))
        XCTAssertEqual(browser.tabMultiSelection.selectedIDs, Set(ids))
        XCTAssertEqual(
            BrowserSidebarSelection.request(
                for: .folder(folder.id), browser: browser,
                reorder: interaction.sidebarReorderState)?.ids, ids)
    }

    func testLogicalOrderIncludesPinsMixedFoldersKeptSplitAndVisibleSections() throws {
        var session = makeSession(count: 8)
        let ids = session.spaces[0].tabs.map(\.id)
        let parent = BrowserFolder(title: "Parent")
        let child = BrowserFolder(title: "Child", parentID: parent.id, isCollapsed: true)
        let empty = BrowserFolder(title: "Empty", orderAnchorTabID: ids[1])
        session.spaces[0].folders = [parent, child, empty]
        session.spaces[0].tabs[0].placement = .pinned
        for index in 1...4 { session.spaces[0].tabs[index].placement = .saved }
        for index in 2...3 { session.spaces[0].tabs[index].folderID = child.id }
        let group = SplitGroupID()
        for index in 2...3 { session.spaces[0].tabs[index].splitGroupID = group }
        session.spaces[0].tabs[4].folderID = parent.id
        session.spaces[0].tabs[7] = .startPage()
        session.spaces[0].isSavedTabsExpanded = true
        let browser = makeBatchStore(session, showing: [session.spaces[0].id: ids[2]])
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let space = try XCTUnwrap(browser.selectedSpace)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        interaction.reconcileCollapsedFolders(
            in: space, selectedTabID: browser.selectedTabID(in: space.id), residentTabIDs: [ids[2], ids[3]])
        XCTAssertEqual(
            BrowserSidebarSelection.itemUnits(in: browser, reorder: interaction.sidebarReorderState),
            [
                [.tab(ids[0])], [.folder(empty.id)], [.tab(ids[1])], [.folder(parent.id)], [.folder(child.id)],
                [.tab(ids[2]), .tab(ids[3])], [.tab(ids[4])], [.tab(ids[5])], [.tab(ids[6])],
            ])
        browser.setSavedTabsExpanded(false, matching: assignment)
        XCTAssertEqual(
            BrowserSidebarSelection.units(in: browser, reorder: interaction.sidebarReorderState),
            [[ids[0]], [ids[5]], [ids[6]]])
        XCTAssertEqual(
            BrowserPlatformSidebarSelectionOrder.orderedItems(
                in: browser,
                assignment: BrowserSpaceRuntimeAssignment(spaceID: space.id, profileID: UUID())), [])
    }

    func testCollapsedVisibilitySurvivesUnmountingButIsScopedToWindowAssignmentAndResidency() throws {
        var session = makeSession(count: 3)
        let folder = BrowserFolder(title: "Kept", location: .current, isCollapsed: true)
        session.spaces[0].folders = [folder]
        let ids = session.spaces[0].tabs.map(\.id)
        for index in 0...1 { session.spaces[0].tabs[index].folderID = folder.id }
        let firstBrowser = BrowserStore(session: session)
        let secondBrowser = BrowserStore(session: session)
        let first = BrowserSidebarInteractionState.connected(to: firstBrowser)
        let second = BrowserSidebarInteractionState.connected(to: secondBrowser)
        var space = session.spaces[0]
        let assignment = BrowserFolderRuntimeAssignment(
            folderID: folder.id, spaceID: space.id,
            profileID: space.profile.id)
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[0], residentTabIDs: [ids[0], ids[1]])
        second.reconcileCollapsedFolders(in: space, selectedTabID: ids[1], residentTabIDs: [ids[0], ids[1]])
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[2], residentTabIDs: [ids[0], ids[1]])
        second.reconcileCollapsedFolders(in: space, selectedTabID: ids[2], residentTabIDs: [ids[0], ids[1]])
        XCTAssertEqual(first.collapsedFolderVisibility(for: assignment).state.keptTabID, ids[0])
        XCTAssertEqual(second.collapsedFolderVisibility(for: assignment).state.keptTabID, ids[1])
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[2], residentTabIDs: [ids[1]])
        XCTAssertNil(first.collapsedFolderVisibility(for: assignment).state.keptTabID)
        XCTAssertEqual(second.collapsedFolderVisibility(for: assignment).state.keptTabID, ids[1])
        space.folders[0].isCollapsed = false
        second.reconcileCollapsedFolders(in: space, selectedTabID: ids[2], residentTabIDs: [ids[0], ids[1]])
        XCTAssertNil(second.collapsedFolderVisibility(for: assignment).state.keptTabID)
        space.folders[0].isCollapsed = true
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[0], residentTabIDs: [ids[0]])
        let oldBox = first.collapsedFolderVisibility(for: assignment)
        first.pruneCollapsedFolders(in: [])
        XCTAssertNil(oldBox.state.keptTabID)
        XCTAssertFalse(first.collapsedFolderVisibility(for: assignment) === oldBox)
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[0], residentTabIDs: [ids[0]])
        let previousProfileBox = first.collapsedFolderVisibility(for: assignment)
        space = BrowserSpace(
            id: space.id, profile: BrowsingProfile(), name: space.name, symbol: space.symbol, accent: space.accent,
            folders: space.folders, tabs: space.tabs)
        first.pruneCollapsedFolders(in: [space])
        XCTAssertNil(previousProfileBox.state.keptTabID)
        let newAssignment = BrowserFolderRuntimeAssignment(
            folderID: folder.id, spaceID: space.id,
            profileID: space.profile.id)
        first.reconcileCollapsedFolders(in: space, selectedTabID: ids[0], residentTabIDs: [ids[0]])
        XCTAssertEqual(first.collapsedFolderVisibility(for: newAssignment).state.keptTabID, ids[0])
        first.browserWillResetSession()
        XCTAssertNil(first.collapsedFolderVisibility(for: newAssignment).state.keptTabID)
    }

    func testLogicalSelectionDoesNotExposeALockedSpaceWithoutLiveAuthorization() throws {
        var session = makeSession(count: 2)
        session.spaces[0].accessPolicy = .deviceOwnerAuthentication
        let browser = BrowserStore(session: session)
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        XCTAssertEqual(BrowserSidebarSelection.itemUnits(in: browser, reorder: interaction.sidebarReorderState), [])
        let access = BrowserSpaceAccessController()
        interaction.sidebarSpaceAccess = access
        XCTAssertEqual(BrowserSidebarSelection.itemUnits(in: browser, reorder: interaction.sidebarReorderState), [])
    }

    /// Prepares the batch through the store's command path and adopts the
    /// prepared session only when the whole batch is accepted.
    @discardableResult
    private func applyBatch(
        _ request: BrowserTabBatchRequest, action: BrowserTabBatchAction, fallbackTabID: TabID? = nil,
        to session: inout BrowserSession
    ) throws -> BrowserTabBatchResult {
        let browser = makeBatchStore(session, fallbackTabID: fallbackTabID)
        let prepared = try browser.prepareTabBatch(request, action: action)
        session = prepared.session
        return prepared.result
    }

    /// A store showing the first Space with `showing` as each Space's tab (the
    /// first tab when empty). `fallbackTabID` is the tab shown just before, so
    /// dismissing the shown tab returns to it.
    private func makeBatchStore(
        _ session: BrowserSession, showing tabs: [SpaceID: TabID] = [:], fallbackTabID: TabID? = nil
    ) -> BrowserStore {
        let preferences = BrowserLinkPreferenceStore(persistence: InMemoryBrowserLinkPreferencesPersistence())
        preferences.followsTabsMovedToAnotherSpace = false
        let spaceID = session.spaces[0].id
        let shown = tabs.isEmpty ? session.spaces[0].tabs.first.map { [spaceID: $0.id] } ?? [:] : tabs
        var opening = shown
        if let fallbackTabID { opening[spaceID] = fallbackTabID }
        let browser = BrowserStore(session: session, showing: spaceID, tabs: opening, linkPreferences: preferences)
        if fallbackTabID != nil, let shownTab = shown[spaceID] { browser.activateSessionTab(shownTab, in: spaceID) }
        return browser
    }

    /// Organizes a fixture through the store's commands in its first Space.
    private func organized(
        _ session: BrowserSession, _ build: (BrowserStore, BrowserSpace) throws -> Void
    ) throws -> BrowserSession {
        let browser = makeBatchStore(session)
        try build(browser, try XCTUnwrap(browser.selectedSpace))
        return browser.session
    }

    private func dragItem(_ tabID: TabID, in space: BrowserSpace) -> BrowserTabDragItem {
        BrowserTabDragItem(tabID: tabID, spaceID: space.id, profileID: space.profile.id)
    }

    private func makeSession(count: Int) -> BrowserSession {
        var space = BrowserSession.makeBlankSpace(number: 1)
        space.tabs = (0..<count).map { index in
            BrowserTab(
                title: "Tab \(index)", url: URL(string: "https://example.com/\(index)"), symbol: "globe",
                placement: .current)
        }
        return BrowserSession(spaces: [space])
    }
}
