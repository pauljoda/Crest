/// Applies a resolved sidebar reorder using the existing move actions, so the
/// model rules (locked spaces, cross-profile checks, folder cycles, ordering)
/// stay in one place.
@MainActor
struct BrowserSidebarReorderCommit {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    @discardableResult
    func apply(
        _ target: BrowserSidebarReorderTarget,
        for item: BrowserSidebarReorderItem
    ) -> Bool {
        switch item {
        case .tab(let tabItem):
            return applyTab(target, for: tabItem)
        case .folder(let folderItem):
            return applyFolder(target, for: folderItem)
        case .splitGroup(let groupItem):
            return applySplitGroup(target, for: groupItem)
        }
    }

    private func applyTab(
        _ target: BrowserSidebarReorderTarget,
        for item: BrowserTabDragItem
    ) -> Bool {
        let action = BrowserTabDragAction(
            browser: browser,
            spaceAccess: spaceAccess
        )

        switch target.kind {
        case .createCurrentFolder(let targetID):
            guard targetID != item.tabID,
                action.canMove(item, into: item.spaceAssignment),
                let space = browser.space(matching: item.spaceAssignment),
                let target = space.currentTabs.first(where: { $0.id == targetID }),
                !target.isStartPage, target.splitGroupID == nil,
                target.folderID == nil
            else { return false }
            return browser.createTabFolder([targetID, item.tabID], in: item.spaceAssignment.spaceID) != nil
        case .space(let destination):
            guard
                action.selectDestination(
                    destination,
                    for: item,
                    using: { browser.selectSpace($0) }
                )
            else { return false }
            return action.move(item, into: destination)

        case .intoFolder(let folderID):
            guard action.canMove(item, into: item.spaceAssignment),
                let folder = browser.space(matching: item.spaceAssignment)?.folders.first(where: { $0.id == folderID })
            else { return false }
            return browser.fileTabs(
                [item.tabID], matching: item.spaceAssignment, into: folderID, location: folder.location)

        case .insert(let section, let beforeID, _):
            guard case .tabs(let placement, let folderID) = section else { return false }
            if placement != .pinned,
                let source = browser.space(matching: item.spaceAssignment)?.tabs.first(where: { $0.id == item.tabID }),
                source.splitGroupID == nil || folderID != nil || source.folderID != nil || beforeID?.folderID != nil
            {
                guard action.canMove(item, into: item.spaceAssignment) else { return false }
                return browser.fileTabs(
                    [item.tabID], matching: item.spaceAssignment, into: folderID,
                    location: placement == .current ? .current : .saved,
                    before: anchorTabID(beforeID, in: item.spaceAssignment), beforeFolderID: beforeID?.folderID)
            }
            return action.move(
                item, to: placement, folderID: folderID,
                before: anchorTabID(beforeID, in: item.spaceAssignment), matching: item.spaceAssignment)

        case .splitInsert(let assignment, let index):
            // The cards on show are the selected tab's group, so the selected
            // tab is the member the dropped tab joins. `addTabToSplit` creates
            // the group when there is none, which is how a window presenting
            // one tab becomes a split.
            guard action.canMove(item, into: assignment),
                let joiningTabID = browser.space(matching: assignment)?.selectedTabID
            else { return false }
            return browser.addTabToSplit(item, joining: joiningTabID, at: index)
        }
    }

    private func applyFolder(
        _ target: BrowserSidebarReorderTarget,
        for item: BrowserFolderDragItem
    ) -> Bool {
        guard
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: item.spaceAssignment, in: browser, accessController: spaceAccess) != nil
        else { return false }
        guard let space = browser.space(matching: item.spaceAssignment),
            let folder = space.folders.first(where: { $0.id == item.folderID })
        else { return false }
        if let captured = item.memberTabIDs {
            let subtree = space.folderTree.descendants(of: folder.id).union([folder.id])
            let live = space.tabs.filter { $0.folderID.map(subtree.contains) == true }.map(\.id)
            guard Set(captured) == Set(live), captured.count == live.count else { return false }
        }
        switch target.kind {
        case .space, .splitInsert, .createCurrentFolder: return false
        case .intoFolder(let parentID):
            guard let parent = space.folders.first(where: { $0.id == parentID }) else { return false }
            return browser.moveFolder(folder.id, matching: item.spaceAssignment, to: parent.location, into: parentID)
        case .insert(let section, let beforeID, _):
            switch section {
            case .folders(let parentID):
                let location = parentID.flatMap { id in space.folders.first { $0.id == id }?.location } ?? .saved
                return browser.moveFolder(
                    folder.id, matching: item.spaceAssignment, to: location,
                    into: parentID, before: beforeID?.folderID)
            case .tabs(let placement, let parentID):
                guard placement != .pinned else { return false }
                return browser.moveFolder(
                    folder.id, matching: item.spaceAssignment,
                    to: placement == .current ? .current : .saved, into: parentID,
                    before: beforeID?.folderID, beforeTabID: anchorTabID(beforeID, in: item.spaceAssignment))
            }
        }
    }

    /// A group commits as one ordered block. Space targets, folder nesting, and
    /// the content area are refused rather than approximated: a split never
    /// spans Spaces, dropping a run "inside" a collapsed folder has no defined
    /// member order yet, and dragging a whole group onto the cards on show would
    /// have to mean "present these instead", which is not a gesture this release
    /// defines.
    private func applySplitGroup(
        _ target: BrowserSidebarReorderTarget,
        for item: BrowserSplitGroupDragItem
    ) -> Bool {
        switch target.kind {
        case .space, .intoFolder, .splitInsert, .createCurrentFolder:
            return false

        case .insert(let section, let beforeID, _):
            guard case .tabs(let placement, let folderID) = section,
                BrowserSplitGroupPolicy.allowsMembership(placement: placement)
            else { return false }
            let action = BrowserTabDragAction(browser: browser, spaceAccess: spaceAccess)
            guard action.canMove(item, into: item.spaceAssignment),
                browser.session.selectedSpaceID == item.spaceID,
                let space = browser.space(matching: item.spaceAssignment)
            else { return false }
            let anchor = anchorTabID(beforeID, in: item.spaceAssignment)
            if beforeID?.folderID == nil, let anchor {
                guard
                    space.tabs.contains(where: {
                        $0.id == anchor && $0.placement == placement && $0.folderID == folderID
                    })
                else { return false }
            }
            return browser.fileTabs(
                space.splitGroupMembers(of: item.groupID).map(\.id), matching: item.spaceAssignment,
                into: folderID, location: placement == .current ? .current : .saved,
                before: anchor, beforeFolderID: beforeID?.folderID)
        }
    }

    /// The tab a drop anchored on `beforeID` lands in front of.
    ///
    /// A group row stands for its whole run, so anchoring on one means landing
    /// before its first member. Resolving that here is what keeps a drop above a
    /// group from silently appending to the end of the section instead.
    private func anchorTabID(
        _ beforeID: BrowserSidebarReorderItemID?,
        in assignment: BrowserSpaceRuntimeAssignment
    ) -> TabID? {
        switch beforeID {
        case .tab(let tabID):
            return tabID
        case .splitGroup(let groupID):
            return browser.space(matching: assignment)?
                .splitGroupMembers(of: groupID)
                .first?
                .id
        case .folder(let folderID):
            guard let space = browser.space(matching: assignment) else { return nil }
            let ids = space.folderTree.descendants(of: folderID).union([folderID])
            return space.tabs.first { $0.folderID.map(ids.contains) == true }?.id
        case .none:
            return nil
        }
    }
}
