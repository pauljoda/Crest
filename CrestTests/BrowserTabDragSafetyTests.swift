import Foundation
import XCTest

@testable import Crest

#if os(macOS)
    import AppKit
#endif

@MainActor
final class BrowserTabDragSafetyTests: XCTestCase {
    func testPointerContinuationSurvivesSourceReleaseAndFinishesOnce() throws {
        let context = makeContext()
        let state = context.sidebarInteraction.sidebarReorderState
        let reorder = BrowserSidebarReorderContext(
            browser: context.browser, spaceAccess: context.spaceAccess, state: state)
        let source = BrowserSidebarReorderInputSession.Source(
            item: .tab(context.item), section: .tabs(placement: .current, folderID: nil))
        state.begin(item: source.item, section: source.section, at: .zero)
        var input: BrowserSidebarReorderInputSession? = BrowserSidebarReorderInputSession()
        weak let retainedInput = input
        var releases = 0
        input?.retainPointerContinuation(
            source: source, reorder: reorder,
            windowDrop: BrowserSidebarWindowDrop(perform: { _ in
                releases += 1
                return true
            }))
        input = nil
        XCTAssertNotNil(retainedInput, "The window session owns input after the row disappears.")
        state.forwardPointerContinuation(at: CGPoint(x: 20, y: 90), released: false, eventTimestamp: 1)
        XCTAssertEqual(state.pointer, CGPoint(x: 20, y: 90))
        state.forwardPointerContinuation(at: CGPoint(x: 20, y: 10), released: false, eventTimestamp: 2)
        XCTAssertEqual(state.pointer, CGPoint(x: 20, y: 10), "The offscreen source can reverse direction.")
        state.forwardPointerContinuation(at: CGPoint(x: 20, y: 15), released: true, eventTimestamp: 3)
        state.forwardPointerContinuation(at: CGPoint(x: 20, y: 15), released: true, eventTimestamp: 3)
        XCTAssertEqual(releases, 1)
        XCTAssertFalse(state.hasLiftInFlight)
        XCTAssertNil(retainedInput, "Ending releases the captured source and window-drop handler.")
    }

    func testPointerContinuationRechecksSourceAuthorizationAndRejectsStaleSessions() throws {
        let context = makeContext()
        let state = context.sidebarInteraction.sidebarReorderState
        let reorder = BrowserSidebarReorderContext(
            browser: context.browser, spaceAccess: context.spaceAccess, state: state)
        let source = BrowserSidebarReorderInputSession.Source(
            item: .tab(context.item), section: .tabs(placement: .current, folderID: nil))
        state.begin(item: source.item, section: source.section, at: .zero)
        let staleToken = try XCTUnwrap(state.sessionToken)
        let input = BrowserSidebarReorderInputSession()
        input.retainPointerContinuation(source: source, reorder: reorder, windowDrop: nil)
        // Selecting a destination Space does not revoke the captured source.
        context.browser.selectSpace(context.destination.id)
        state.forwardPointerContinuation(at: CGPoint(x: 10, y: 20), released: false, eventTimestamp: 1)
        XCTAssertTrue(state.hasLiftInFlight)
        replaceProfile(matching: context.sourceAssignment, with: Self.uuid(99), in: context.browser)
        state.forwardPointerContinuation(at: CGPoint(x: 10, y: 30), released: false, eventTimestamp: 2)
        XCTAssertFalse(state.hasLiftInFlight)
        state.begin(item: source.item, section: source.section, at: .zero)
        var staleCalls = 0
        state.retainPointerContinuation(session: staleToken) { _, _ in staleCalls += 1 }
        state.forwardPointerContinuation(at: CGPoint(x: 10, y: 40), released: true, eventTimestamp: 3)
        XCTAssertEqual(staleCalls, 0)
        XCTAssertTrue(state.hasLiftInFlight)
        state.cancel()
    }

    func testPointerContinuationCommitsAllFortyMembersWhenOnlySixteenSourceRowsAreMeasured() throws {
        let tabs = (1...42).map { index in
            Self.makeTab(
                id: Self.tabID(UInt8(index)), title: "Tab \(index)",
                placement: index == 42 ? .saved : .current)
        }
        let space = Self.makeSpace(id: Self.spaceID(90), profileID: Self.uuid(91), name: "Source", tabs: tabs)
        let browser = Self.makeBrowser(spaces: [space], selectedSpaceID: space.id)
        let interaction = BrowserSidebarInteractionState.connected(to: browser)
        let state = interaction.sidebarReorderState
        let access = BrowserSpaceAccessController(authenticator: InMemoryAuthenticator())
        let reorder = BrowserSidebarReorderContext(browser: browser, spaceAccess: access, state: state)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let current = BrowserSidebarReorderSection.tabs(placement: .current, folderID: nil)
        let saved = BrowserSidebarReorderSection.tabs(placement: .saved, folderID: nil)
        for (index, tab) in tabs.prefix(16).enumerated() {
            state.register(
                row: BrowserSidebarReorderRow(
                    id: .tab(tab.id), space: assignment, section: current,
                    frame: CGRect(x: 0, y: index * 44, width: 200, height: 44)), owner: UUID())
        }
        let anchor = try XCTUnwrap(tabs.last)
        let targetFrame = CGRect(x: 400, y: 900, width: 200, height: 44)
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(anchor.id), space: assignment, section: saved,
                frame: targetFrame), owner: UUID())
        state.register(zone: BrowserSidebarReorderZone(target: .section(saved), frame: targetFrame), for: UUID())
        let request = BrowserTabBatchRequest(ids: tabs.prefix(40).map(\.id), in: space)
        let source = BrowserSidebarReorderInputSession.Source(
            item: .tab(BrowserTabDragItem(tabID: tabs[0].id, spaceID: space.id, profileID: space.profile.id)),
            section: current)
        state.begin(item: source.item.selecting(request), section: current, at: CGPoint(x: 10, y: 10))
        let input = BrowserSidebarReorderInputSession()
        input.retainPointerContinuation(source: source, reorder: reorder, windowDrop: nil)
        let point = CGPoint(x: targetFrame.midX, y: targetFrame.minY + 1)
        state.forwardPointerContinuation(at: point, released: false, eventTimestamp: 1)
        XCTAssertEqual(state.resolvedTarget?.kind, .insert(section: saved, beforeID: .tab(anchor.id), index: 0))
        XCTAssertEqual(state.lift?.item.selection?.ids, request.ids)
        state.forwardPointerContinuation(at: point, released: true, eventTimestamp: 2)
        XCTAssertEqual(browser.selectedSpace?.savedTabs.map(\.id), request.ids + [anchor.id])
        XCTAssertEqual(browser.selectedSpace?.currentTabs.map(\.id), [tabs[40].id])
        XCTAssertFalse(state.hasLiftInFlight)
    }

    #if os(macOS)
        func testNativePointerContinuationRejectsForeignWindowsDeduplicatesPanesAndCancelsOnClose() throws {
            let context = makeContext()
            let state = context.sidebarInteraction.sidebarReorderState
            let window = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [], backing: .buffered, defer: false)
            let foreign = NSWindow(
                contentRect: CGRect(x: 0, y: 0, width: 400, height: 500),
                styleMask: [], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            foreign.isReleasedWhenClosed = false
            defer {
                window.close()
                foreign.close()
            }
            let first = BrowserTabSelectionMonitor.SelectionView(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
            let second = BrowserTabSelectionMonitor.SelectionView(frame: first.frame)
            for view in [first, second] {
                view.sidebarInteraction = context.sidebarInteraction
                view.globalFrame = CGRect(x: 30, y: 40, width: 400, height: 500)
                window.contentView?.addSubview(view)
            }
            // A retained pager pane can have a translated native frame; its SwiftUI
            // global origin cancels that translation when mapping the window point.
            second.frame.origin = CGPoint(x: 400, y: 100)
            second.globalFrame.origin = CGPoint(x: 430, y: -60)
            state.begin(item: .tab(context.item), section: .tabs(placement: .current, folderID: nil), at: .zero)
            var points: [CGPoint] = []
            state.retainPointerContinuation(session: try XCTUnwrap(state.sessionToken)) { point, _ in
                points.append(point)
            }
            func event(in window: NSWindow, timestamp: TimeInterval) throws -> NSEvent {
                try XCTUnwrap(
                    NSEvent.mouseEvent(
                        with: .leftMouseDragged, location: CGPoint(x: 10, y: 20),
                        modifierFlags: [], timestamp: timestamp, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            }
            _ = first.handle(try event(in: foreign, timestamp: 1))
            XCTAssertTrue(points.isEmpty)
            let move = try event(in: window, timestamp: 2)
            _ = first.handle(move)
            _ = second.handle(move)
            XCTAssertEqual(points, [CGPoint(x: 40, y: 520)])
            first.stop()  // Recycling one Space pane does not cancel the window's session.
            _ = second.handle(try event(in: window, timestamp: 3))
            XCTAssertEqual(points, [CGPoint(x: 40, y: 520), CGPoint(x: 40, y: 520)])
            XCTAssertTrue(state.hasLiftInFlight)
            NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
            XCTAssertFalse(state.hasLiftInFlight)
            _ = second.handle(try event(in: window, timestamp: 4))
            XCTAssertEqual(points.count, 2)
            second.stop()
        }
    #endif

    func testExactUnlockedDragActionMovesOnlyIntoItsCapturedDestination() throws {
        let context = makeContext()
        let action = BrowserTabDragAction(
            browser: context.browser,
            spaceAccess: context.spaceAccess
        )

        XCTAssertTrue(action.canMove(context.item, into: context.destinationAssignment))
        context.browser.selectSpace(context.destinationAssignment.spaceID)
        XCTAssertTrue(
            action.move(
                context.item,
                to: .pinned,
                matching: context.destinationAssignment
            )
        )

        let source = try XCTUnwrap(
            context.browser.session.space(id: context.sourceAssignment.spaceID)
        )
        let destination = try XCTUnwrap(
            context.browser.session.space(id: context.destinationAssignment.spaceID)
        )
        XCTAssertFalse(source.tabs.contains(where: { $0.id == context.tab.id }))
        XCTAssertEqual(
            destination.tabs.first(where: { $0.id == context.tab.id })?.placement,
            .pinned
        )
    }

    func testDragActionRejectsLockedSourceAndDestinationSpaces() {
        let lockedSource = makeContext(sourceAccessPolicy: .deviceOwnerAuthentication)
        let lockedSourceAction = BrowserTabDragAction(
            browser: lockedSource.browser,
            spaceAccess: lockedSource.spaceAccess
        )
        XCTAssertFalse(
            lockedSourceAction.canMove(
                lockedSource.item,
                into: lockedSource.destinationAssignment
            )
        )

        let lockedDestination = makeContext(
            destinationAccessPolicy: .deviceOwnerAuthentication
        )
        let lockedDestinationAction = BrowserTabDragAction(
            browser: lockedDestination.browser,
            spaceAccess: lockedDestination.spaceAccess
        )
        XCTAssertFalse(
            lockedDestinationAction.canMove(
                lockedDestination.item,
                into: lockedDestination.destinationAssignment
            )
        )
    }

    func testDragActionRejectsReplacedSourceAndDestinationProfiles() {
        let replacedSource = makeContext()
        let replacedSourceAction = BrowserTabDragAction(
            browser: replacedSource.browser,
            spaceAccess: replacedSource.spaceAccess
        )
        replaceProfile(
            matching: replacedSource.sourceAssignment,
            with: Self.uuid(20),
            in: replacedSource.browser
        )
        XCTAssertFalse(
            replacedSourceAction.canMove(
                replacedSource.item,
                into: replacedSource.destinationAssignment
            )
        )

        let replacedDestination = makeContext()
        let replacedDestinationAction = BrowserTabDragAction(
            browser: replacedDestination.browser,
            spaceAccess: replacedDestination.spaceAccess
        )
        replaceProfile(
            matching: replacedDestination.destinationAssignment,
            with: Self.uuid(21),
            in: replacedDestination.browser
        )
        XCTAssertFalse(
            replacedDestinationAction.canMove(
                replacedDestination.item,
                into: replacedDestination.destinationAssignment
            )
        )
    }

    func testDragActionRejectsDeletingSourceAndDestinationSpaces() {
        let deletingSource = makeContext()
        let deletingSourceAction = BrowserTabDragAction(
            browser: deletingSource.browser,
            spaceAccess: deletingSource.spaceAccess
        )
        XCTAssertTrue(
            deletingSource.browser.family.beginDeletingSpace(
                deletingSource.sourceAssignment.spaceID
            )
        )
        defer {
            deletingSource.browser.family.finishDeletingSpace(
                deletingSource.sourceAssignment.spaceID
            )
        }
        XCTAssertFalse(
            deletingSourceAction.canMove(
                deletingSource.item,
                into: deletingSource.destinationAssignment
            )
        )

        let deletingDestination = makeContext()
        let deletingDestinationAction = BrowserTabDragAction(
            browser: deletingDestination.browser,
            spaceAccess: deletingDestination.spaceAccess
        )
        XCTAssertTrue(
            deletingDestination.browser.family.beginDeletingSpace(
                deletingDestination.destinationAssignment.spaceID
            )
        )
        defer {
            deletingDestination.browser.family.finishDeletingSpace(
                deletingDestination.destinationAssignment.spaceID
            )
        }
        XCTAssertFalse(
            deletingDestinationAction.canMove(
                deletingDestination.item,
                into: deletingDestination.destinationAssignment
            )
        )
    }

    func testStaleDragSessionCannotEndANewerDragWithTheSameTabID() {
        let context = makeContext()
        let firstSession: BrowserDragSessionToken = context.sidebarInteraction.tabDragState.begin(
            item: context.item,
            placement: context.tab.placement
        )
        let secondSession: BrowserDragSessionToken = context.sidebarInteraction.tabDragState.begin(
            item: context.item,
            placement: context.tab.placement
        )

        XCTAssertNotEqual(firstSession, secondSession)
        context.sidebarInteraction.tabDragState.end(session: firstSession)
        XCTAssertEqual(context.sidebarInteraction.tabDragState.item, context.item)
        XCTAssertEqual(context.sidebarInteraction.tabDragState.sessionToken, secondSession)

        context.sidebarInteraction.tabDragState.end(session: secondSession)
        XCTAssertNil(context.sidebarInteraction.tabDragState.item)
        XCTAssertNil(context.sidebarInteraction.tabDragState.sessionToken)
    }

    func testRepairedDuplicateIDsRejectTheStaleDragAndMoveOnlyTheCapturedSource() throws {
        let duplicateTabID = Self.tabID(30)
        let decoyTab = Self.makeTab(
            id: duplicateTabID,
            title: "Decoy",
            placement: .current
        )
        let capturedTab = Self.makeTab(
            id: duplicateTabID,
            title: "Captured",
            placement: .current
        )
        let decoy = Self.makeSpace(
            id: Self.spaceID(31),
            profileID: Self.uuid(32),
            name: "Decoy Source",
            tabs: [decoyTab]
        )
        let capturedSource = Self.makeSpace(
            id: Self.spaceID(33),
            profileID: Self.uuid(34),
            name: "Captured Source",
            tabs: [capturedTab]
        )
        let destination = Self.makeSpace(
            id: Self.spaceID(35),
            profileID: Self.uuid(36),
            name: "Destination",
            tabs: []
        )
        var restored = BrowserSession(spaces: [decoy, capturedSource, destination])
        restored = try BrowserCoreSync.repair(restored)
        let browser = BrowserStore(
            session: restored, showing: destination.id)
        let repairedID = try XCTUnwrap(restored.space(id: capturedSource.id)?.tabs.first?.id)
        XCTAssertNotEqual(repairedID, duplicateTabID)
        let stale = BrowserTabDragItem(tabID: duplicateTabID, spaceID: capturedSource.id, profileID: capturedSource.profile.id)
        let before = browser.session
        XCTAssertFalse(browser.moveTab(stale, to: .pinned, matching: BrowserSpaceRuntimeAssignment(space: destination)))
        XCTAssertEqual(browser.session, before)
        let item = BrowserTabDragItem(
            tabID: repairedID,
            spaceID: capturedSource.id,
            profileID: capturedSource.profile.id
        )
        let sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        let token = sidebarInteraction.tabDragState.begin(item: item, placement: .current)
        defer { sidebarInteraction.tabDragState.end(session: token) }

        XCTAssertTrue(
            browser.moveTab(
                item,
                to: .pinned,
                matching: BrowserSpaceRuntimeAssignment(space: destination)
            )
        )

        let currentDecoy = try XCTUnwrap(browser.session.space(id: decoy.id))
        let currentSource = try XCTUnwrap(
            browser.session.space(id: capturedSource.id)
        )
        let currentDestination = try XCTUnwrap(
            browser.session.space(id: destination.id)
        )
        XCTAssertEqual(currentDecoy.tabs.map(\.title), ["Decoy"])
        XCTAssertTrue(currentSource.tabs.isEmpty)
        XCTAssertEqual(currentDestination.tabs.filter { !$0.isStartPage }.map(\.title), ["Captured"])
        XCTAssertEqual(currentDestination.tabs.first?.placement, .pinned)
    }

    func testStaleMenuCloseAndDeleteActionsRejectChangedPlacement() throws {
        let closeContext = makeContext(sourcePlacement: .current)
        let closeAction = BrowserTabOrganizationAction(
            browser: closeContext.browser,
            spaceAccess: closeContext.spaceAccess
        )
        XCTAssertTrue(
            closeContext.browser.moveTab(
                closeContext.tab.id,
                matching: closeContext.sourceAssignment,
                to: .pinned
            )
        )
        XCTAssertFalse(
            closeAction.close(
                closeContext.item.runtimeAssignment,
                expectedPlacement: .current
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                closeContext.browser.session.space(
                    id: closeContext.sourceAssignment.spaceID
                )
            ).tabs.first(where: { $0.id == closeContext.tab.id })?.placement,
            .pinned
        )

        let deleteContext = makeContext(sourcePlacement: .pinned)
        let deleteAction = BrowserTabOrganizationAction(
            browser: deleteContext.browser,
            spaceAccess: deleteContext.spaceAccess
        )
        XCTAssertTrue(
            deleteContext.browser.moveTab(
                deleteContext.tab.id,
                matching: deleteContext.sourceAssignment,
                to: .saved
            )
        )
        XCTAssertFalse(
            deleteAction.delete(
                deleteContext.item.runtimeAssignment,
                expectedPlacement: .pinned
            )
        )
        XCTAssertEqual(
            try XCTUnwrap(
                deleteContext.browser.session.space(
                    id: deleteContext.sourceAssignment.spaceID
                )
            ).tabs.first(where: { $0.id == deleteContext.tab.id })?.placement,
            .saved
        )
    }

    // MARK: - Split group drags

    /// A resolved section drop routes the whole run through `moveSplitGroup`,
    /// keeping the members contiguous and in order at their new anchor.
    func testSplitGroupDropCommitsTheWholeRunThroughMoveSplitGroup() throws {
        let context = makeSplitContext()
        let commit = BrowserSidebarReorderCommit(
            browser: context.browser,
            spaceAccess: context.spaceAccess
        )

        // Appending: the run leaves its place at the head of the list and lands
        // after the tab that was behind it.
        XCTAssertTrue(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .insert(
                        section: .tabs(placement: .current, folderID: nil),
                        beforeID: nil,
                        index: 1
                    )
                ),
                for: .splitGroup(context.item)
            )
        )

        let space = try XCTUnwrap(
            context.browser.session.space(id: context.assignment.spaceID)
        )
        XCTAssertEqual(
            space.tabs.map(\.title),
            ["Outsider", "Head", "Tail"]
        )
        XCTAssertEqual(
            space.splitGroupMembers(of: context.groupID).map(\.title),
            ["Head", "Tail"],
            "The run must stay contiguous after the move."
        )
    }

    /// The whole mobile lift, at the state level: `.onDrag` stages the group,
    /// the sidebar's drop delegate promotes it with its first position, and the
    /// release commits the run.
    ///
    /// Geometry is mobile-shaped — one tall group row and one tab row inside a
    /// phone-width section — because the group registers a single reorder row
    /// for the whole stack, and the neighbour has to step over all of it.
    func testAStagedMobileSplitGroupLiftPromotesAndCommitsTheWholeRun() throws {
        let context = makeSplitContext()
        let state = context.sidebarInteraction.sidebarReorderState
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let groupFrame = CGRect(x: 8, y: 110, width: 374, height: 120)
        let outsiderFrame = CGRect(x: 8, y: 230, width: 374, height: 44)
        state.register(
            row: BrowserSidebarReorderRow(
                id: .splitGroup(context.groupID),
                space: context.assignment,
                section: section,
                frame: groupFrame
            ),
            owner: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(context.outsider.id),
                space: context.assignment,
                section: section,
                frame: outsiderFrame
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

        state.stage(item: .splitGroup(context.item), section: section)
        XCTAssertFalse(state.isDragging)

        // Past the tab's midpoint: the group lands behind it.
        state.update(pointer: CGPoint(x: 195, y: 260))
        XCTAssertTrue(state.isLifted(.splitGroup(context.groupID)))
        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: section, beforeID: nil, index: 1)
        )
        XCTAssertEqual(
            state.displacement(for: .tab(context.outsider.id)),
            CGSize(width: 0, height: -groupFrame.height),
            "The neighbour steps over the group's whole stack, not one member."
        )

        let drop = try XCTUnwrap(state.end())
        XCTAssertEqual(drop.item, .splitGroup(context.item))
        XCTAssertTrue(
            BrowserSidebarReorderCommit(
                browser: context.browser,
                spaceAccess: context.spaceAccess
            )
            .apply(drop.target, for: drop.item)
        )

        let space = try XCTUnwrap(
            context.browser.session.space(id: context.assignment.spaceID)
        )
        XCTAssertEqual(space.tabs.map(\.title), ["Outsider", "Head", "Tail"])
        XCTAssertEqual(
            space.splitGroupMembers(of: context.groupID).map(\.title),
            ["Head", "Tail"]
        )
    }

    /// Pinning by drag is a lift that resolves the pinned grid: the pointer
    /// entering the grid is what opens the tile slot and morphs the preview into
    /// a tile, and nothing else in the drag reaches that state. Only a split
    /// group is refused there — see
    /// `testSplitGroupDropsRefusePinnedFolderAndSpaceTargets`.
    func testAPlainTabLiftedFromTheCurrentRunCanTargetThePinnedGrid() {
        let firstPin = Self.makeTab(
            id: Self.tabID(60),
            title: "First Pin",
            placement: .pinned
        )
        let secondPin = Self.makeTab(
            id: Self.tabID(61),
            title: "Second Pin",
            placement: .pinned
        )
        let current = Self.makeTab(
            id: Self.tabID(62),
            title: "Current",
            placement: .current
        )
        let space = Self.makeSpace(
            id: Self.spaceID(63),
            profileID: Self.uuid(64),
            name: "Pinning",
            tabs: [firstPin, secondPin, current]
        )
        let browser = Self.makeBrowser(
            spaces: [space]
        )
        let sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        let state = sidebarInteraction.sidebarReorderState
        let pinned = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let currentSection = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let firstTile = CGRect(x: 8, y: 60, width: 88, height: 64)
        let secondTile = CGRect(x: 100, y: 60, width: 88, height: 64)
        let currentRow = CGRect(x: 8, y: 260, width: 374, height: 44)

        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(firstPin.id),
                space: BrowserSpaceRuntimeAssignment(space: space),
                section: pinned,
                frame: firstTile
            ),
            owner: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(secondPin.id),
                space: BrowserSpaceRuntimeAssignment(space: space),
                section: pinned,
                frame: secondTile
            ),
            owner: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(current.id),
                space: BrowserSpaceRuntimeAssignment(space: space),
                section: currentSection,
                frame: currentRow
            ),
            owner: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(pinned),
                frame: CGRect(x: 8, y: 60, width: 374, height: 64)
            ),
            for: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(currentSection),
                frame: CGRect(x: 8, y: 240, width: 374, height: 300)
            ),
            for: UUID()
        )

        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: current.id,
                    spaceID: space.id,
                    profileID: space.profile.id
                )
            ),
            section: currentSection,
            at: CGPoint(x: currentRow.midX, y: currentRow.midY)
        )
        state.update(
            pointer: CGPoint(x: secondTile.midX, y: secondTile.midY)
        )

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(
                section: pinned,
                beforeID: .tab(secondPin.id),
                index: 1
            ),
            "A tab held over the pinned grid must resolve a pinned insertion."
        )
        XCTAssertEqual(
            state.liftTargetShape,
            .pinnedTile,
            "The lift morphs into what release would make of it."
        )
    }

    /// A collapsed folder is the one target whose meaning a section's zone
    /// cannot express — release lands the item *inside* it, not beside it — so
    /// the row has to say so while the lift is still in flight. The reorder
    /// state is the only thing that knows, and this is the pairing the folder
    /// header's highlight is drawn from.
    func testACollapsedFolderReportsItselfAsTheNestingTargetWhileLifted() {
        let context = makeSplitContext()
        let state = context.sidebarInteraction.sidebarReorderState
        let folderID = FolderID()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let rowFrame = CGRect(x: 8, y: 154, width: 374, height: 44)
        let folderFrame = CGRect(x: 8, y: 300, width: 374, height: 44)

        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(context.outsider.id),
                space: context.assignment,
                section: section,
                frame: rowFrame
            ),
            owner: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(section),
                frame: CGRect(x: 0, y: 100, width: 390, height: 120)
            ),
            for: UUID()
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .folder(folderID),
                frame: BrowserSidebarReorderPolicy.nestingFrame(
                    for: folderFrame
                )
            ),
            for: UUID()
        )

        XCTAssertFalse(
            state.isTargetedFolder(folderID),
            "Nothing is lifted, so nothing can be aimed at the folder."
        )

        let item = BrowserTabDragItem(
            tabID: context.outsider.id,
            spaceID: context.space.id,
            profileID: context.space.profile.id
        )
        state.begin(
            item: .tab(item),
            section: section,
            at: CGPoint(x: rowFrame.midX, y: rowFrame.midY)
        )
        state.update(pointer: CGPoint(x: rowFrame.midX, y: rowFrame.midY))
        XCTAssertFalse(state.isTargetedFolder(folderID))

        state.update(
            pointer: CGPoint(x: folderFrame.midX, y: folderFrame.midY)
        )
        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .intoFolder(folderID)
        )
        XCTAssertTrue(state.isTargetedFolder(folderID))
        // The lift's own kind is what the header reads to choose between the
        // row highlight and the nesting outline.
        XCTAssertEqual(state.lift?.item, .tab(item))
        XCTAssertTrue(
            BrowserFolderRowPresentationPolicy.showsDropHighlight(
                for: state.lift?.item
            )
        )

        _ = state.end()
        XCTAssertFalse(
            state.isTargetedFolder(folderID),
            "A settled list must not keep drawing the last target."
        )
    }

    /// Anchoring on a group row means landing before its first member. Without
    /// that mapping the drop would silently append to the end of the section.
    func testATabDroppedOnAGroupRowLandsBeforeItsFirstMember() throws {
        let context = makeSplitContext()
        let commit = BrowserSidebarReorderCommit(
            browser: context.browser,
            spaceAccess: context.spaceAccess
        )
        let outsiderItem = BrowserTabDragItem(
            tabID: context.outsider.id,
            spaceID: context.assignment.spaceID,
            profileID: context.assignment.profileID
        )

        XCTAssertTrue(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .insert(
                        section: .tabs(placement: .current, folderID: nil),
                        beforeID: .splitGroup(context.groupID),
                        index: 0
                    )
                ),
                for: .tab(outsiderItem)
            )
        )

        let space = try XCTUnwrap(
            context.browser.session.space(id: context.assignment.spaceID)
        )
        XCTAssertEqual(space.tabs.map(\.title), ["Outsider", "Head", "Tail"])
    }

    func testIndividualMemberDropsDetachWithoutMovingTheSurvivingSplit() throws {
        for memberIndex in 0...1 {
            for destination in SplitMemberDropDestination.allCases {
                let member = Self.makeTab(
                    id: Self.tabID(56), title: "Moved Member", placement: .current,
                    splitGroupID: SplitGroupID(rawValue: Self.uuid(50)))
                let context = makeSplitContext(adding: member, at: memberIndex)
                let folder = try XCTUnwrap(context.browser.addFolder(in: context.space.id))
                let originalMembers = context.members
                let item = BrowserTabDragItem(
                    tabID: member.id, spaceID: context.space.id, profileID: context.space.profile.id)
                let kind: BrowserSidebarReorderTarget.Kind =
                    switch destination {
                    case .beforeGroup:
                        .insert(
                            section: .tabs(placement: .current, folderID: nil), beforeID: .splitGroup(context.groupID),
                            index: 0)
                    case .beforeFolder:
                        .insert(section: .tabs(placement: .saved, folderID: nil), beforeID: .folder(folder), index: 0)
                    case .insideFolder: .intoFolder(folder)
                    case .newFolder: .createCurrentFolder(context.outsider.id)
                    case .pinned: .insert(section: .tabs(placement: .pinned, folderID: nil), beforeID: nil, index: 0)
                    }

                XCTAssertTrue(
                    BrowserSidebarReorderCommit(browser: context.browser, spaceAccess: context.spaceAccess)
                        .apply(BrowserSidebarReorderTarget(kind: kind), for: .tab(item)), "\(destination)")

                let updated = try XCTUnwrap(context.browser.selectedSpace)
                XCTAssertEqual(updated.splitGroupMembers(of: context.groupID), originalMembers, "\(destination)")
                let moved = try XCTUnwrap(updated.tabs.first { $0.id == member.id })
                XCTAssertNil(moved.splitGroupID, "\(destination)")
                XCTAssertEqual(moved.url, member.url)
                XCTAssertEqual(updated.tabs.count, context.space.tabs.count)
                switch destination {
                case .beforeGroup: XCTAssertEqual(updated.tabs.first?.id, member.id)
                case .beforeFolder: XCTAssertEqual(moved.placement, .saved)
                case .insideFolder: XCTAssertEqual(moved.folderID, folder)
                case .newFolder:
                    XCTAssertNotNil(moved.folderID)
                    XCTAssertEqual(updated.tabs.first { $0.id == context.outsider.id }?.folderID, moved.folderID)
                case .pinned: XCTAssertEqual(moved.placement, .pinned)
                }
            }
        }
    }

    func testRefusedMemberDropLeavesTheOriginalSplitIntact() {
        let context = makeSplitContext()
        let item = BrowserTabDragItem(
            tabID: context.members[0].id, spaceID: context.space.id, profileID: context.space.profile.id)
        let commit = BrowserSidebarReorderCommit(browser: context.browser, spaceAccess: context.spaceAccess)
        let before = context.browser.session

        XCTAssertFalse(commit.apply(BrowserSidebarReorderTarget(kind: .intoFolder(FolderID())), for: .tab(item)))
        XCTAssertFalse(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .insert(section: .tabs(placement: .saved, folderID: nil), beforeID: .tab(TabID()), index: 0)),
                for: .tab(item)))
        XCTAssertEqual(context.browser.session, before)
    }

    /// Pinned tabs cannot be split members, and a group is not a folder or Space
    /// payload, so those targets commit nothing at all.
    func testSplitGroupDropsRefusePinnedFolderAndSpaceTargets() {
        let context = makeSplitContext()
        let commit = BrowserSidebarReorderCommit(
            browser: context.browser,
            spaceAccess: context.spaceAccess
        )
        let original = context.browser.session

        XCTAssertFalse(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .insert(
                        section: .tabs(placement: .pinned, folderID: nil),
                        beforeID: nil,
                        index: 0
                    )
                ),
                for: .splitGroup(context.item)
            )
        )
        XCTAssertFalse(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .insert(
                        section: .folders(parentID: nil),
                        beforeID: nil,
                        index: 0
                    )
                ),
                for: .splitGroup(context.item)
            )
        )
        XCTAssertFalse(
            commit.apply(
                BrowserSidebarReorderTarget(kind: .intoFolder(FolderID())),
                for: .splitGroup(context.item)
            )
        )
        XCTAssertFalse(
            commit.apply(
                BrowserSidebarReorderTarget(kind: .space(context.assignment)),
                for: .splitGroup(context.item)
            )
        )
        XCTAssertEqual(context.browser.session, original)
    }

    /// The group guard reuses the tab guard's access rules: a locked Space refuses
    /// the move, and so does a Space whose profile was replaced under the drag.
    func testSplitGroupMovesRefuseLockedAndForeignSpaces() {
        let locked = makeSplitContext(accessPolicy: .deviceOwnerAuthentication)
        let lockedAction = BrowserTabDragAction(
            browser: locked.browser,
            spaceAccess: locked.spaceAccess
        )
        XCTAssertFalse(lockedAction.canMove(locked.item, into: locked.assignment))
        XCTAssertFalse(
            lockedAction.move(
                locked.item,
                to: .current,
                matching: locked.assignment
            )
        )

        let foreign = makeSplitContext()
        let foreignAction = BrowserTabDragAction(
            browser: foreign.browser,
            spaceAccess: foreign.spaceAccess
        )
        XCTAssertFalse(
            foreignAction.canMove(
                foreign.item,
                into: BrowserSpaceRuntimeAssignment(
                    spaceID: foreign.assignment.spaceID,
                    profileID: Self.uuid(60)
                )
            ),
            "A split never spans Spaces, so only its own assignment can accept it."
        )
        XCTAssertFalse(
            foreignAction.canMove(
                BrowserSplitGroupDragItem(
                    groupID: SplitGroupID(rawValue: Self.uuid(61)),
                    spaceID: foreign.assignment.spaceID,
                    profileID: foreign.assignment.profileID,
                    memberTabIDs: foreign.item.memberTabIDs
                ),
                into: foreign.assignment
            ),
            "A group the Space no longer holds cannot move."
        )
    }

    // MARK: - Drag to split

    /// A drop on the content area joins the selected tab's group at the slot the
    /// pointer resolved, and the newcomer takes focus.
    func testAContentAreaDropJoinsTheSelectedTabsSplitAtThatSlot() throws {
        let context = makeSplitContext()
        let commit = BrowserSidebarReorderCommit(
            browser: context.browser,
            spaceAccess: context.spaceAccess
        )
        let outsiderItem = BrowserTabDragItem(
            tabID: context.outsider.id,
            spaceID: context.assignment.spaceID,
            profileID: context.assignment.profileID
        )

        XCTAssertTrue(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .splitInsert(assignment: context.assignment, index: 1)
                ),
                for: .tab(outsiderItem)
            )
        )

        let space = try XCTUnwrap(
            context.browser.session.space(id: context.assignment.spaceID)
        )
        XCTAssertEqual(space.tabs.map(\.title), ["Head", "Outsider", "Tail"])
        XCTAssertEqual(
            space.splitGroupMembers(of: context.groupID).map(\.title),
            ["Head", "Outsider", "Tail"]
        )
        XCTAssertEqual(context.browser.selectedTabID(in: space.id), context.outsider.id)
    }

    /// The first drop is the same commit as every later one: a window presenting
    /// one tab has a group created around it.
    func testAContentAreaDropOnALoneTabCreatesTheSplit() throws {
        let selected = Self.makeTab(
            id: Self.tabID(70),
            title: "Selected",
            placement: .current
        )
        let joiner = Self.makeTab(
            id: Self.tabID(71),
            title: "Joiner",
            placement: .current
        )
        let space = Self.makeSpace(
            id: Self.spaceID(72),
            profileID: Self.uuid(73),
            name: "Unsplit",
            tabs: [selected, joiner]
        )
        let browser = Self.makeBrowser(spaces: [space], selectedSpaceID: space.id)
        let assignment = BrowserSpaceRuntimeAssignment(space: space)
        let commit = BrowserSidebarReorderCommit(
            browser: browser,
            spaceAccess: BrowserSpaceAccessController(
                authenticator: InMemoryAuthenticator()
            )
        )

        XCTAssertTrue(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .splitInsert(assignment: assignment, index: 0)
                ),
                for: .tab(
                    BrowserTabDragItem(
                        tabID: joiner.id,
                        spaceID: assignment.spaceID,
                        profileID: assignment.profileID
                    )
                )
            )
        )

        let updated = try XCTUnwrap(browser.session.space(id: space.id))
        XCTAssertEqual(updated.tabs.map(\.title), ["Joiner", "Selected"])
        let groupID = try XCTUnwrap(updated.tabs.first?.splitGroupID)
        XCTAssertEqual(
            updated.splitGroupMembers(of: groupID).map(\.title),
            ["Joiner", "Selected"]
        )
        XCTAssertEqual(browser.selectedTabID(in: space.id), joiner.id)
    }

    /// Only a tab becomes a card, and only in its own window's Space. Everything
    /// else the content area could be handed commits nothing at all.
    func testContentAreaDropsRefuseFoldersGroupsAndForeignSpaces() {
        let context = makeSplitContext()
        let commit = BrowserSidebarReorderCommit(
            browser: context.browser,
            spaceAccess: context.spaceAccess
        )
        let original = context.browser.session
        let target = BrowserSidebarReorderTarget(
            kind: .splitInsert(assignment: context.assignment, index: 0)
        )

        XCTAssertFalse(
            commit.apply(
                target,
                for: .folder(
                    BrowserFolderDragItem(
                        folderID: FolderID(),
                        spaceID: context.assignment.spaceID,
                        profileID: context.assignment.profileID
                    )
                )
            )
        )
        XCTAssertFalse(commit.apply(target, for: .splitGroup(context.item)))
        XCTAssertFalse(
            commit.apply(
                BrowserSidebarReorderTarget(
                    kind: .splitInsert(
                        assignment: BrowserSpaceRuntimeAssignment(
                            spaceID: Self.spaceID(74),
                            profileID: Self.uuid(75)
                        ),
                        index: 0
                    )
                ),
                for: .tab(
                    BrowserTabDragItem(
                        tabID: context.outsider.id,
                        spaceID: context.assignment.spaceID,
                        profileID: context.assignment.profileID
                    )
                )
            )
        )
        XCTAssertEqual(context.browser.session, original)
    }

    func testOffscreenExpandedFolderCannotStealAPinnedDrop() {
        let context = makeSplitContext()
        let state = context.sidebarInteraction.sidebarReorderState
        let scrollRegionID = UUID()
        let viewport = CGRect(x: 8, y: 220, width: 374, height: 320)
        let currentSection = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let savedSection = BrowserSidebarReorderSection.tabs(
            placement: .saved,
            folderID: nil
        )
        let pinnedSection = BrowserSidebarReorderSection.tabs(
            placement: .pinned,
            folderID: nil
        )
        let sourceFrame = CGRect(x: 8, y: 420, width: 374, height: 44)

        state.register(scrollRegionFrame: viewport, for: scrollRegionID)
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(context.outsider.id),
                space: context.assignment,
                section: currentSection,
                frame: sourceFrame
            ),
            owner: UUID(),
            scrollRegionID: scrollRegionID
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(savedSection),
                frame: CGRect(x: 8, y: -600, width: 374, height: 1_000)
            ),
            for: UUID(),
            scrollRegionID: scrollRegionID
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .folder(FolderID()),
                frame: CGRect(x: 8, y: 64, width: 374, height: 44)
            ),
            for: UUID(),
            scrollRegionID: scrollRegionID
        )
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(pinnedSection),
                frame: CGRect(x: 8, y: 48, width: 374, height: 96)
            ),
            for: UUID()
        )

        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: context.outsider.id,
                    spaceID: context.assignment.spaceID,
                    profileID: context.assignment.profileID
                )
            ),
            section: currentSection,
            at: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        )
        state.update(pointer: CGPoint(x: sourceFrame.midX, y: 86))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: pinnedSection, beforeID: nil, index: 0),
            "Expanded saved folders above the scroll viewport must not cover "
                + "the fixed pinned grid in the drag registry."
        )
    }

    func testScrollingDuringLiftMovesFrozenRowsAndAcceptsNewLazyRows() {
        let context = makeSplitContext()
        let state = context.sidebarInteraction.sidebarReorderState
        let scrollRegionID = UUID()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let sourceFrame = CGRect(x: 8, y: 300, width: 374, height: 44)
        let neighbourFrame = CGRect(x: 8, y: 344, width: 374, height: 44)

        state.register(
            scrollRegionFrame: CGRect(x: 8, y: 200, width: 374, height: 300),
            for: scrollRegionID
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(context.outsider.id),
                space: context.assignment,
                section: section,
                frame: sourceFrame
            ),
            owner: UUID(),
            scrollRegionID: scrollRegionID
        )
        let neighbourID = BrowserSidebarReorderItemID.tab(Self.tabID(76))
        state.register(
            row: BrowserSidebarReorderRow(
                id: neighbourID,
                space: context.assignment,
                section: section,
                frame: neighbourFrame
            ),
            owner: UUID(),
            scrollRegionID: scrollRegionID
        )
        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: context.outsider.id,
                    spaceID: context.assignment.spaceID,
                    profileID: context.assignment.profileID
                )
            ),
            section: section,
            at: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        )

        state.scrollableContentDidMove(in: scrollRegionID, by: -80)
        XCTAssertEqual(
            state.frame(ofRow: neighbourID),
            neighbourFrame.offsetBy(dx: 0, dy: -80)
        )

        let newlyVisibleID = BrowserSidebarReorderItemID.tab(Self.tabID(77))
        let newlyVisibleFrame = CGRect(x: 8, y: 430, width: 374, height: 44)
        state.register(
            row: BrowserSidebarReorderRow(
                id: newlyVisibleID,
                space: context.assignment,
                section: section,
                frame: newlyVisibleFrame
            ),
            owner: UUID(),
            scrollRegionID: scrollRegionID
        )

        XCTAssertEqual(state.frame(ofRow: newlyVisibleID), newlyVisibleFrame)
    }

    func testOffscreenRowsStillCountTowardAScrolledSectionsInsertionIndex() {
        let context = makeSplitContext()
        let state = context.sidebarInteraction.sidebarReorderState
        let scrollRegionID = UUID()
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let viewport = CGRect(x: 8, y: 200, width: 374, height: 300)
        let offscreenFrame = CGRect(x: 8, y: 100, width: 374, height: 44)
        let sourceFrame = CGRect(x: 8, y: 300, width: 374, height: 44)
        let targetFrame = CGRect(x: 8, y: 344, width: 374, height: 44)

        state.register(scrollRegionFrame: viewport, for: scrollRegionID)
        state.register(
            zone: BrowserSidebarReorderZone(
                target: .section(section),
                frame: viewport
            ),
            for: UUID(),
            scrollRegionID: scrollRegionID
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(Self.tabID(78)),
                space: context.assignment,
                section: section,
                frame: offscreenFrame
            ),
            owner: UUID(),
            scrollRegionID: scrollRegionID
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(context.outsider.id),
                space: context.assignment,
                section: section,
                frame: sourceFrame
            ),
            owner: UUID(),
            scrollRegionID: scrollRegionID
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(Self.tabID(79)),
                space: context.assignment,
                section: section,
                frame: targetFrame
            ),
            owner: UUID(),
            scrollRegionID: scrollRegionID
        )

        state.begin(
            item: .tab(
                BrowserTabDragItem(
                    tabID: context.outsider.id,
                    spaceID: context.assignment.spaceID,
                    profileID: context.assignment.profileID
                )
            ),
            section: section,
            at: CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
        )
        state.update(pointer: CGPoint(x: targetFrame.midX, y: targetFrame.maxY))

        XCTAssertEqual(
            state.resolvedTarget?.kind,
            .insert(section: section, beforeID: nil, index: 2),
            "Offscreen predecessors remain part of the model order even though "
                + "their zones cannot target fixed chrome outside the viewport."
        )
    }

    /// A Space whose first tabs, Head and Tail, are one split, then Outsider;
    /// `member` joins the split at `index` among them when given.
    private func makeSplitContext(
        accessPolicy: BrowserSpaceAccessPolicy = .open, adding member: BrowserTab? = nil, at index: Int = 0
    ) -> SplitContext {
        let groupID = SplitGroupID(rawValue: Self.uuid(50))
        let head = Self.makeTab(
            id: Self.tabID(51),
            title: "Head",
            placement: .current,
            splitGroupID: groupID
        )
        let tail = Self.makeTab(
            id: Self.tabID(52),
            title: "Tail",
            placement: .current,
            splitGroupID: groupID
        )
        let outsider = Self.makeTab(
            id: Self.tabID(53),
            title: "Outsider",
            placement: .current
        )
        var tabs = [head, tail, outsider]
        if let member { tabs.insert(member, at: index) }
        let space = Self.makeSpace(
            id: Self.spaceID(54),
            profileID: Self.uuid(55),
            name: "Split Source",
            tabs: tabs,
            accessPolicy: accessPolicy
        )
        return SplitContext(
            browser: Self.makeBrowser(spaces: [space]),
            spaceAccess: BrowserSpaceAccessController(
                authenticator: InMemoryAuthenticator()
            ),
            space: space,
            groupID: groupID,
            members: [head, tail],
            outsider: outsider
        )
    }

    private enum SplitMemberDropDestination: CaseIterable {
        case beforeGroup, beforeFolder, insideFolder, newFolder, pinned
    }

    private func makeContext(
        sourceAccessPolicy: BrowserSpaceAccessPolicy = .open,
        destinationAccessPolicy: BrowserSpaceAccessPolicy = .open,
        sourcePlacement: TabPlacement = .current
    ) -> Context {
        let tab = Self.makeTab(
            id: Self.tabID(40),
            title: "Captured Tab",
            placement: sourcePlacement
        )
        let source = Self.makeSpace(
            id: Self.spaceID(41),
            profileID: Self.uuid(42),
            name: "Source",
            tabs: [tab],
            accessPolicy: sourceAccessPolicy
        )
        let destination = Self.makeSpace(
            id: Self.spaceID(43),
            profileID: Self.uuid(44),
            name: "Destination",
            tabs: [],
            accessPolicy: destinationAccessPolicy
        )
        return Context(
            browser: Self.makeBrowser(spaces: [source, destination]),
            spaceAccess: BrowserSpaceAccessController(
                authenticator: InMemoryAuthenticator()
            ),
            source: source,
            destination: destination,
            tab: tab
        )
    }

    private func replaceProfile(
        matching assignment: BrowserSpaceRuntimeAssignment,
        with profileID: UUID,
        in browser: BrowserStore
    ) {
        browser.replaceProfileForTesting(of: assignment.spaceID, with: profileID)
    }

    /// A window showing `selectedSpaceID` (else the first Space), with every
    /// Space showing its first tab.
    private static func makeBrowser(
        spaces: [BrowserSpace],
        selectedSpaceID: SpaceID? = nil
    ) -> BrowserStore {
        var tabs: [SpaceID: TabID] = [:]
        for space in spaces {
            tabs[space.id] = space.tabs.first?.id
        }
        return BrowserStore(
            session: BrowserSession(spaces: spaces),
            showing: selectedSpaceID ?? spaces.first?.id ?? SpaceID(), tabs: tabs
        )
    }

    private static func makeSpace(
        id: SpaceID,
        profileID: UUID,
        name: String,
        tabs: [BrowserTab],
        accessPolicy: BrowserSpaceAccessPolicy = .open
    ) -> BrowserSpace {
        BrowserSpace(
            id: id,
            profile: BrowsingProfile(id: profileID),
            name: name,
            symbol: "rectangle.stack",
            accent: .indigo,
            folders: [],
            tabs: tabs,
            accessPolicy: accessPolicy
        )
    }

    private static func makeTab(
        id: TabID,
        title: String,
        placement: TabPlacement,
        splitGroupID: SplitGroupID? = nil
    ) -> BrowserTab {
        BrowserTab(
            id: id,
            title: title,
            url: URL(fileURLWithPath: "/crest-tab-drag-safety/\(title)"),
            placement: placement,
            splitGroupID: splitGroupID,
            lastActivatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private static func tabID(_ finalByte: UInt8) -> TabID {
        TabID(rawValue: uuid(finalByte))
    }

    private static func spaceID(_ finalByte: UInt8) -> SpaceID {
        SpaceID(rawValue: uuid(finalByte))
    }

    private static func uuid(_ finalByte: UInt8) -> UUID {
        UUID(
            uuid: (
                0x54, 0x41, 0x42, 0x44, 0x52, 0x41, 0x47, 0x53,
                0x41, 0x46, 0x45, 0x54, 0x59, 0x00, 0x00, finalByte
            )
        )
    }

    @MainActor
    private struct Context {
        let sidebarInteraction: BrowserSidebarInteractionState
        let browser: BrowserStore
        let spaceAccess: BrowserSpaceAccessController
        let source: BrowserSpace
        let destination: BrowserSpace
        let tab: BrowserTab

        init(
            browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, source: BrowserSpace,
            destination: BrowserSpace, tab: BrowserTab
        ) {
            self.browser = browser
            self.spaceAccess = spaceAccess
            self.source = source
            self.destination = destination
            self.tab = tab
            sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        }

        var sourceAssignment: BrowserSpaceRuntimeAssignment {
            BrowserSpaceRuntimeAssignment(space: source)
        }

        var destinationAssignment: BrowserSpaceRuntimeAssignment {
            BrowserSpaceRuntimeAssignment(space: destination)
        }

        var item: BrowserTabDragItem {
            BrowserTabDragItem(
                tabID: tab.id,
                spaceID: source.id,
                profileID: source.profile.id
            )
        }
    }

    @MainActor
    private struct SplitContext {
        let sidebarInteraction: BrowserSidebarInteractionState
        let browser: BrowserStore
        let spaceAccess: BrowserSpaceAccessController
        let space: BrowserSpace
        let groupID: SplitGroupID
        let members: [BrowserTab]
        let outsider: BrowserTab

        init(
            browser: BrowserStore, spaceAccess: BrowserSpaceAccessController, space: BrowserSpace,
            groupID: SplitGroupID, members: [BrowserTab], outsider: BrowserTab
        ) {
            self.browser = browser
            self.spaceAccess = spaceAccess
            self.space = space
            self.groupID = groupID
            self.members = members
            self.outsider = outsider
            sidebarInteraction = BrowserSidebarInteractionState.connected(to: browser)
        }

        var assignment: BrowserSpaceRuntimeAssignment {
            BrowserSpaceRuntimeAssignment(space: space)
        }

        var item: BrowserSplitGroupDragItem {
            BrowserSplitGroupDragItem(
                groupID: groupID,
                spaceID: space.id,
                profileID: space.profile.id,
                memberTabIDs: members.map(\.id)
            )
        }
    }

    private final class InMemoryAuthenticator: BrowserDeviceAuthenticating {
        func authenticate(reason _: String) async throws -> Bool {
            true
        }
    }
}
