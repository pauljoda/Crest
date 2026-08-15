@MainActor
struct BrowserTabDragAction {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController

    func canMove(
        _ item: BrowserTabDragItem,
        into destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard
            let source = BrowserSidebarAccessPolicy.unlockedSpace(
                matching: item.spaceAssignment,
                in: browser,
                accessController: spaceAccess
            ),
            source.tabs.contains(where: { $0.id == item.tabID }),
            BrowserSidebarAccessPolicy.unlockedSpace(
                matching: destination,
                in: browser,
                accessController: spaceAccess
            ) != nil
        else { return false }

        return item.spaceAssignment == destination
            || browser.canMoveTab(
                item.tabID,
                matching: item.spaceAssignment,
                into: destination
            )
    }

    @discardableResult
    func selectDestination(
        _ destination: BrowserSpaceRuntimeAssignment,
        for item: BrowserTabDragItem,
        using select: (SpaceID) -> Void
    ) -> Bool {
        guard canMove(item, into: destination) else { return false }
        select(destination.spaceID)
        return BrowserSidebarAccessPolicy.selectedUnlockedSpace(
            matching: destination,
            in: browser,
            accessController: spaceAccess
        ) != nil
    }

    @discardableResult
    func move(
        _ item: BrowserTabDragItem,
        into destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard canMove(item, into: destination) else { return false }
        return item.spaceAssignment == destination
            || browser.moveTab(item, into: destination)
    }

    @discardableResult
    func move(
        _ item: BrowserTabDragItem,
        to placement: TabPlacement,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        matching destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard canMove(item, into: destination) else { return false }
        return browser.moveTab(
            item,
            to: placement,
            folderID: folderID,
            before: destinationTabID,
            matching: destination
        )
    }

    /// A split group never leaves the Space it was lifted from, so the only
    /// destination it can have is its own. Everything else is the same guard a
    /// tab gets: the Space must be unlocked and must still hold the run.
    func canMove(
        _ item: BrowserSplitGroupDragItem,
        into destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard item.spaceAssignment == destination,
            let source = BrowserSidebarAccessPolicy.unlockedSpace(
                matching: item.spaceAssignment,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        return source.tabs.contains { $0.splitGroupID == item.groupID }
    }

    @discardableResult
    func move(
        _ item: BrowserSplitGroupDragItem,
        to placement: TabPlacement,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        matching destination: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard canMove(item, into: destination) else { return false }
        return browser.moveSplitGroup(
            item.groupID,
            matching: destination,
            to: placement,
            folderID: folderID,
            before: destinationTabID
        )
    }
}
