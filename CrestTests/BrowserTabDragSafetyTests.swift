import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserTabDragSafetyTests: XCTestCase {
    func testDragItemExposesItsExactRuntimeAssignment() {
        let item = BrowserTabDragItem(
            tabID: Self.tabID(1),
            spaceID: Self.spaceID(2),
            profileID: Self.uuid(3)
        )

        XCTAssertEqual(
            item.runtimeAssignment,
            BrowserTabRuntimeAssignment(
                tabID: Self.tabID(1),
                spaceID: Self.spaceID(2),
                profileID: Self.uuid(3)
            )
        )
    }

    func testExactUnlockedDragActionMovesOnlyIntoItsCapturedDestination() throws {
        let context = makeContext()
        let action = BrowserTabDragAction(
            browser: context.browser,
            spaceAccess: context.spaceAccess
        )

        XCTAssertTrue(action.canMove(context.item, into: context.destinationAssignment))
        XCTAssertTrue(
            action.selectDestination(
                context.destinationAssignment,
                for: context.item,
                using: context.browser.selectSpace
            )
        )
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
        let firstSession: BrowserDragSessionToken = context.browser.tabDragState.begin(
            item: context.item,
            placement: context.tab.placement
        )
        let secondSession: BrowserDragSessionToken = context.browser.tabDragState.begin(
            item: context.item,
            placement: context.tab.placement
        )

        XCTAssertNotEqual(firstSession, secondSession)
        context.browser.tabDragState.end(session: firstSession)
        XCTAssertEqual(context.browser.tabDragState.item, context.item)
        XCTAssertEqual(context.browser.tabDragState.sessionToken, secondSession)

        context.browser.tabDragState.end(session: secondSession)
        XCTAssertNil(context.browser.tabDragState.item)
        XCTAssertNil(context.browser.tabDragState.sessionToken)
    }

    func testExactStoreMoveWithDuplicateTabIDsMutatesOnlyTheCapturedSource() throws {
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
        let browser = Self.makeBrowser(
            spaces: [decoy, capturedSource, destination],
            selectedSpaceID: destination.id
        )
        let item = BrowserTabDragItem(
            tabID: duplicateTabID,
            spaceID: capturedSource.id,
            profileID: capturedSource.profile.id
        )
        let token = browser.tabDragState.begin(item: item, placement: .current)
        defer { browser.tabDragState.end(session: token) }

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
        XCTAssertEqual(currentDestination.tabs.map(\.title), ["Captured"])
        XCTAssertEqual(currentDestination.tabs.first?.placement, .pinned)
    }

    func testExactStoreMoveRejectsADuplicateTabIDInTheDestination() {
        let duplicateTabID = Self.tabID(37)
        let sourceTab = Self.makeTab(
            id: duplicateTabID,
            title: "Source",
            placement: .current
        )
        let destinationTab = Self.makeTab(
            id: duplicateTabID,
            title: "Destination",
            placement: .saved
        )
        let source = Self.makeSpace(
            id: Self.spaceID(38),
            profileID: Self.uuid(39),
            name: "Source",
            tabs: [sourceTab]
        )
        let destination = Self.makeSpace(
            id: Self.spaceID(40),
            profileID: Self.uuid(41),
            name: "Destination",
            tabs: [destinationTab]
        )
        let browser = Self.makeBrowser(
            spaces: [source, destination],
            selectedSpaceID: destination.id
        )
        let originalSession = browser.session
        let item = BrowserTabDragItem(
            tabID: duplicateTabID,
            spaceID: source.id,
            profileID: source.profile.id
        )
        let destinationAssignment = BrowserSpaceRuntimeAssignment(
            space: destination
        )
        let action = BrowserTabDragAction(
            browser: browser,
            spaceAccess: BrowserSpaceAccessController(
                authenticator: InMemoryAuthenticator()
            )
        )

        XCTAssertFalse(action.canMove(item, into: destinationAssignment))
        XCTAssertFalse(
            action.move(
                item,
                to: .pinned,
                matching: destinationAssignment
            )
        )
        XCTAssertEqual(browser.session, originalSession)
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
        let state = context.browser.sidebarReorderState
        let section = BrowserSidebarReorderSection.tabs(
            placement: .current,
            folderID: nil
        )
        let groupFrame = CGRect(x: 8, y: 110, width: 374, height: 120)
        let outsiderFrame = CGRect(x: 8, y: 230, width: 374, height: 44)
        state.register(
            row: BrowserSidebarReorderRow(
                id: .splitGroup(context.groupID),
                section: section,
                frame: groupFrame
            ),
            owner: UUID()
        )
        state.register(
            row: BrowserSidebarReorderRow(
                id: .tab(context.outsider.id),
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

    /// The `.onDrag` provider hands the session a JSON payload. It never leaves
    /// Crest, but it does have to survive the round trip the provider encodes.
    func testTheSplitGroupDragPayloadRoundTripsAsJSON() throws {
        let item = BrowserSplitGroupDragItem(
            groupID: SplitGroupID(rawValue: Self.uuid(70)),
            spaceID: Self.spaceID(71),
            profileID: Self.uuid(72),
            memberTabIDs: [Self.tabID(73), Self.tabID(74)]
        )

        let decoded = try JSONDecoder().decode(
            BrowserSplitGroupDragItem.self,
            from: JSONEncoder().encode(item)
        )

        XCTAssertEqual(decoded, item)
        XCTAssertEqual(decoded.spaceAssignment, item.spaceAssignment)
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
        XCTAssertEqual(space.selectedTabID, context.outsider.id)
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
        XCTAssertEqual(updated.selectedTabID, joiner.id)
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

    private func makeSplitContext(
        accessPolicy: BrowserSpaceAccessPolicy = .open
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
        let space = Self.makeSpace(
            id: Self.spaceID(54),
            profileID: Self.uuid(55),
            name: "Split Source",
            tabs: [head, tail, outsider],
            accessPolicy: accessPolicy
        )
        return SplitContext(
            browser: Self.makeBrowser(
                spaces: [space],
                selectedSpaceID: space.id
            ),
            spaceAccess: BrowserSpaceAccessController(
                authenticator: InMemoryAuthenticator()
            ),
            space: space,
            groupID: groupID,
            members: [head, tail],
            outsider: outsider
        )
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
            browser: Self.makeBrowser(
                spaces: [source, destination],
                selectedSpaceID: source.id
            ),
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
        guard
            let index = browser.session.spaces.firstIndex(where: {
                $0.id == assignment.spaceID
            })
        else {
            XCTFail("Expected the captured Space.")
            return
        }
        let space = browser.session.spaces[index]
        browser.session.spaces[index] = Self.makeSpace(
            id: space.id,
            profileID: profileID,
            name: space.name,
            tabs: space.tabs,
            accessPolicy: space.accessPolicy
        )
    }

    private static func makeBrowser(
        spaces: [BrowserSpace],
        selectedSpaceID: SpaceID
    ) -> BrowserStore {
        BrowserStore(
            session: BrowserSession(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID
            ),
            persistence: InMemoryBrowserSessionPersistence(),
            browsingMode: .privateBrowsing
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
            accessPolicy: accessPolicy,
            selectedTabID: tabs.first?.id
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

    private struct Context {
        let browser: BrowserStore
        let spaceAccess: BrowserSpaceAccessController
        let source: BrowserSpace
        let destination: BrowserSpace
        let tab: BrowserTab

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

    private struct SplitContext {
        let browser: BrowserStore
        let spaceAccess: BrowserSpaceAccessController
        let space: BrowserSpace
        let groupID: SplitGroupID
        let members: [BrowserTab]
        let outsider: BrowserTab

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
