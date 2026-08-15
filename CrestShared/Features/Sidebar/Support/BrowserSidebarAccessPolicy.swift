@MainActor
enum BrowserSidebarAccessPolicy {
    static func availableSpaces(in browser: BrowserStore) -> [BrowserSpace] {
        browser.session.spaces.filter {
            !browser.deletingSpaceIDs.contains($0.id)
        }
    }

    static func unlockedSpace(
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> BrowserSpace? {
        guard let space = browser.space(matching: assignment),
            !accessController.isLocked(space)
        else { return nil }
        return space
    }

    static func selectedUnlockedSpace(
        matching assignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> BrowserSpace? {
        guard browser.session.selectedSpaceID == assignment.spaceID else {
            return nil
        }
        return unlockedSpace(
            matching: assignment,
            in: browser,
            accessController: accessController
        )
    }

    static func showsSelectedSpaceActions(
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> Bool {
        guard let selectedSpace = browser.selectedSpace else { return false }
        return selectedUnlockedSpace(
            matching: BrowserSpaceRuntimeAssignment(space: selectedSpace),
            in: browser,
            accessController: accessController
        ) != nil
    }

    static func availableTabMoveDestinationSpaces(
        from sourceAssignment: BrowserSpaceRuntimeAssignment,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> [BrowserSpace] {
        guard
            selectedUnlockedSpace(
                matching: sourceAssignment,
                in: browser,
                accessController: accessController
            ) != nil
        else { return [] }
        return availableSpaces(in: browser).filter { space in
            space.id != sourceAssignment.spaceID
                && !accessController.isLocked(space)
        }
    }

    static func canSettlePageSelection(
        _ assignment: BrowserSpaceRuntimeAssignment,
        settledSpaceID: SpaceID,
        in browser: BrowserStore,
        accessController: BrowserSpaceAccessController
    ) -> Bool {
        guard settledSpaceID == assignment.spaceID else { return false }
        return selectedUnlockedSpace(
            matching: assignment,
            in: browser,
            accessController: accessController
        ) != nil
    }
}
