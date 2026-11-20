import Foundation

extension BrowserStore {
    /// Closing a saved native view dismisses its presentation, retaining the
    /// document in Saved. Current copies continue through the normal close path.
    func dismissNativeTab(_ id: UUID, matching assignment: BrowserSpaceRuntimeAssignment) {
        guard let space = shownSpace, BrowserSpaceRuntimeAssignment(space: space) == assignment,
            selectedTabID(in: space.id) == id,
            space.shownTab(id)?.nativeContent != nil
        else { return }
        selectDismissalFallback(afterDismissing: id)
    }

    @discardableResult
    func openGettingStarted() -> UUID? {
        openNativeTab(.gettingStarted)
    }

    /// Opens the guide in the Space the core's finish of setup names.
    @discardableResult
    func openGettingStartedAfterSetup(matching assignment: BrowserSpaceRuntimeAssignment)
        -> BrowserTabRuntimeAssignment?
    {
        guard spaceModel(matching: assignment) != nil else { return nil }
        selectSpace(assignment.spaceID)
        guard let tabID = openGettingStarted() else { return nil }
        return BrowserTabRuntimeAssignment(tabID: tabID, spaceID: assignment.spaceID, profileID: assignment.profileID)
    }

    @discardableResult
    func openSettings() -> UUID? {
        openNativeTab(.settings)
    }

    /// Shows `view` in the Space this window shows: its tab there, for a view
    /// a Space keeps one of, or a new tab in the section the view opens in.
    /// Native documents enter the same session mutation and persistence path
    /// as websites, and no page pool or second selection model is owned by the
    /// document.
    @discardableResult
    func openNativeTab(_ view: NativeView) -> UUID? {
        guard let space = shownSpace else { return nil }
        if view.opensOnce, let existing = space.tabs.models.first(where: { $0.nativeView == view }) {
            selectTab(existing.id)
            return existing.id
        }
        return openSessionTab(.view(view), in: space.id, placement: view.placement)
    }
}
