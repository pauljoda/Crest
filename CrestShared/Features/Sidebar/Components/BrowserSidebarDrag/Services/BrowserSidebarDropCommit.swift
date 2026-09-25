import Foundation

/// Commits a sidebar drop as the core's drop intent for its target. Which
/// edit a drop makes, and every rule that refuses it, is the core's, locked
/// and departing Spaces included: this only names where the lift landed, and
/// shows the person a refusal's own words.
@MainActor
struct BrowserSidebarDropCommit {
    // MARK: - Variables

    let browser: BrowserStore

    // MARK: - Actions - Committing

    /// Drops `item`, lifted as `plan` holds it, on `target`, and answers
    /// whether the core took the drop. A refusal is shown in the window's
    /// selection message instead.
    @discardableResult
    func commit(
        _ target: BrowserSidebarReorderTarget, for item: BrowserSidebarReorderItem, plan: BrowserSidebarLiftPlan
    ) -> Bool {
        // The lift names its Space by profile too; a Space replaced under it
        // is not the one it was lifted from.
        let assignment = item.spaceAssignment
        guard let space = browser.spaceModel(assignment.spaceID), space.profileID == assignment.profileID,
            let drop = drop(on: target, lifting: plan.selection, in: space)
        else { return false }
        let source = browser.space(matching: assignment)
        let changes: [Change]
        do {
            changes = try browser.family.commit(drop.intent, from: browser)
        } catch {
            browser.tabMultiSelection.message = error.placementExplanation
            return false
        }
        let copies: [TabCopied] = changes.compactMap {
            guard case .tabCopied(let copied) = $0, copied.workspaceID == browser.family.workspaceID else { return nil }
            return copied
        }
        if let source { browser.prepareAcceptedCopies(copies, from: source) }
        if let destination = drop.following {
            let destinationAssignment = BrowserSpaceRuntimeAssignment(
                spaceID: destination.id, profileID: destination.profileID)
            browser.pendingMovedTabActivation = browser.selectedTabID(in: destination.id).map {
                BrowserTabRuntimeAssignment(
                    tabID: $0, spaceID: destinationAssignment.spaceID, profileID: destinationAssignment.profileID)
            }
            if case .tab(let tab) = item, item.selection == nil {
                browser.interactionObserver?.browserDidMoveTab(from: tab.runtimeAssignment, to: destinationAssignment)
            }
        }
        reselect(after: drop, lifted: item, copies: copies)
        return true
    }

    // MARK: - Actions - Drops

    /// The drop intent for landing the lift on `target`, and the Space the
    /// window follows the lift to, if any.
    private func drop(
        on target: BrowserSidebarReorderTarget, lifting selection: TabSelection, in space: SpaceModel
    ) -> (intent: any SidebarDrop, following: SpaceModel?)? {
        let (workspaceID, windowID, spaceID) = (browser.family.workspaceID, browser.windowID, space.id)
        switch target.kind {
        case .insert(let section, let beforeID, _):
            let placement: TabPlacement
            let folderID: FolderID?
            switch section {
            case .tabs(let tabs, let folder):
                (placement, folderID) = (tabs, folder)
            case .folders(let parentID):
                placement = parentID.flatMap { space.folders.model($0)?.location } ?? .saved
                folderID = parentID
            }
            return (
                DropIntoList(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    section: placement, folderID: folderID,
                    beforeTabID: anchorTabID(beforeID, in: space, lifting: selection),
                    beforeFolderID: beforeID?.folderID),
                nil
            )
        case .intoFolder(let folderID):
            guard let folder = space.folders.model(folderID) else { return nil }
            return (
                DropIntoList(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    section: folder.location, folderID: folderID, beforeTabID: nil, beforeFolderID: nil),
                nil
            )
        case .space(let destination):
            guard let destinationSpace = browser.spaceModel(destination.spaceID),
                destinationSpace.profileID == destination.profileID
            else { return nil }
            let follows = browser.linkPreferences.followsTabsMovedToAnotherSpace
            return (
                DropOnSpace(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    destinationSpaceID: destination.spaceID, follows: follows),
                follows ? destinationSpace : nil
            )
        case .splitInsert(let assignment, let index):
            // The cards on show are the shown tab's split, so the shown tab is
            // the one the lift joins, and a window showing one tab makes a split.
            guard assignment.spaceID == spaceID, let shown = browser.selectedTabID(in: spaceID) else { return nil }
            return (
                DropIntoSplit(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    targetTabID: shown, index: index),
                nil
            )
        case .createCurrentFolder(let tabID):
            return (
                DropAroundTab(
                    workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                    tabID: tabID),
                nil
            )
        }
    }

    /// The tab a drop anchored on `beforeID` lands in front of. A split row
    /// stands for its whole run, so anchoring on one lands before its first
    /// member the lift does not hold, and a folder before its first tab.
    private func anchorTabID(
        _ beforeID: BrowserSidebarReorderItemID?, in space: SpaceModel, lifting selection: TabSelection
    ) -> TabID? {
        let lifted = Set(selection.memberTabIDs)
        switch beforeID {
        case .tab(let tabID):
            return tabID
        case .splitGroup(let groupID):
            return space.splitMembers(of: groupID).first { !lifted.contains($0.id) }?.id
        case .folder(let folderID):
            return space.tabIDs(inFolder: folderID).first { !lifted.contains($0) }
        case .none:
            return nil
        }
    }

    /// A lifted selection stays selected where it landed, its copies in place
    /// of the tabs that stayed behind; one that left the Space is let go.
    private func reselect(
        after drop: (intent: any SidebarDrop, following: SpaceModel?), lifted item: BrowserSidebarReorderItem,
        copies: [TabCopied]
    ) {
        guard let captured = item.selection else { return }
        let selection = browser.tabMultiSelection
        if drop.intent is DropOnSpace {
            selection.clear()
            return
        }
        let copied = Dictionary(uniqueKeysWithValues: copies.map { ($0.sourceTabID, $0.copyTabID) })
        selection.selectAll(
            units: captured.rootItems.map { root in
                guard case .tab(let id) = root, let copy = copied[id] else { return [root] }
                return [.tab(copy)]
            })
    }
}
