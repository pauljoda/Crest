import Foundation

/// Which Spaces of a window's workspace its chrome may show and act on, read
/// from the core's read model: every Space not being deleted or hidden on this
/// device, and of those, the ones this process holds the grant to show.
extension BrowserStore {
    // MARK: - Variables

    /// The core keeps at least one Space shown, so this list empties only
    /// while every Space is going.
    var availableSpaces: [SpaceModel] {
        spaceModels.filter { !isDeleting($0.id) && !hidesSpaceOnDevice($0.id) }
    }

    /// Whether this window's workspace is the person's own session, the only
    /// one whose Spaces a device may hide. The core finds that session the
    /// same way: the workspace whose kind keeps the app's preferences.
    var offersSpaceVisibility: Bool {
        workspaceModel?.kind.keepsAppPreferences == true
    }

    // MARK: - Actions - Device Visibility

    /// Whether this device hides `spaceID`.
    func hidesSpaceOnDevice(_ spaceID: UUID) -> Bool {
        offersSpaceVisibility && core.state.spaceVisibility.hiddenSpaceIDs.contains(spaceID)
    }

    /// Whether Show on This Device may change for `spaceID` now: a hidden
    /// Space may always show again, and a shown one may hide while it is not
    /// the one this window shows and another stays shown. The core refuses
    /// hiding the last Space and moves a window off a Space it hides either
    /// way; this only keeps the switch from offering it.
    func canChangeSpaceVisibility(of spaceID: UUID) -> Bool {
        guard offersSpaceVisibility else { return false }
        if hidesSpaceOnDevice(spaceID) { return true }
        return spaceID != selectedSpaceID && availableSpaces.contains { $0.id != spaceID }
    }

    // MARK: - Actions - Space Access

    func unlockedSpace(
        matching assignment: BrowserSpaceRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> SpaceModel? {
        guard !isDeleting(assignment.spaceID), let space = spaceModel(assignment.spaceID),
            space.profileID == assignment.profileID, !accessController.isLocked(space)
        else { return nil }
        return space
    }

    func selectedUnlockedSpace(
        matching assignment: BrowserSpaceRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> SpaceModel? {
        guard selectedSpaceID == assignment.spaceID else { return nil }
        return unlockedSpace(matching: assignment, accessController: accessController)
    }

    func showsSelectedSpaceActions(accessController: BrowserSpaceAccessController) -> Bool {
        guard let space = shownSpace else { return false }
        return !accessController.isLocked(space)
    }

    func availableTabMoveDestinationSpaces(
        from sourceAssignment: BrowserSpaceRuntimeAssignment,
        accessController: BrowserSpaceAccessController
    ) -> [SpaceModel] {
        guard selectedUnlockedSpace(matching: sourceAssignment, accessController: accessController) != nil
        else { return [] }
        return availableSpaces.filter { space in
            space.id != sourceAssignment.spaceID && !accessController.isLocked(space)
        }
    }
}
