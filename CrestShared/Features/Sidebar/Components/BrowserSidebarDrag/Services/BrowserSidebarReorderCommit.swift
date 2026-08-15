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
        case let .tab(tabItem):
            return applyTab(target, for: tabItem)
        case let .folder(folderItem):
            return applyFolder(target, for: folderItem)
        case let .splitGroup(groupItem):
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
        case let .space(destination):
            guard
                action.selectDestination(
                    destination,
                    for: item,
                    using: { browser.selectSpace($0) }
                )
            else { return false }
            return action.move(item, into: destination)

        case let .intoFolder(folderID):
            return action.move(
                item,
                to: .saved,
                folderID: folderID,
                before: nil,
                matching: item.spaceAssignment
            )

        case let .insert(section, beforeID, _):
            guard case let .tabs(placement, folderID) = section else { return false }
            return action.move(
                item,
                to: placement,
                folderID: folderID,
                before: anchorTabID(beforeID, in: item.spaceAssignment),
                matching: item.spaceAssignment
            )

        case let .splitInsert(assignment, index):
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
        switch target.kind {
        case .space, .splitInsert:
            // Folders belong to a space; moving one between spaces is not a
            // reorder and has no model action. A folder has no page either, so
            // it can never become a card.
            return false

        case let .intoFolder(folderID):
            return browser.moveFolder(
                item,
                matching: item.spaceAssignment,
                into: folderID,
                before: nil
            )

        case let .insert(section, beforeID, _):
            guard case let .folders(parentID) = section else { return false }
            return browser.moveFolder(
                item,
                matching: item.spaceAssignment,
                into: parentID,
                before: beforeID?.folderID
            )
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
        case .space, .intoFolder, .splitInsert:
            return false

        case let .insert(section, beforeID, _):
            guard case let .tabs(placement, folderID) = section,
                BrowserSplitGroupPolicy.allowsMembership(placement: placement)
            else { return false }
            return BrowserTabDragAction(
                browser: browser,
                spaceAccess: spaceAccess
            )
            .move(
                item,
                to: placement,
                folderID: folderID,
                before: anchorTabID(beforeID, in: item.spaceAssignment),
                matching: item.spaceAssignment
            )
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
        case let .tab(tabID):
            return tabID
        case let .splitGroup(groupID):
            return browser.space(matching: assignment)?
                .splitGroupMembers(of: groupID)
                .first?
                .id
        case .folder, .none:
            return nil
        }
    }
}
