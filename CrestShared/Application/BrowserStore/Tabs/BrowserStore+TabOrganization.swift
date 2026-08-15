import Foundation

extension BrowserStore {
    func pinSelectedTab() {
        guard selectedSpace != nil else { return }
        session.moveSelectedTab(to: .pinned)
        persist(scope: .core)
    }

    func pinTab(_ id: TabID) {
        guard selectedSpace?.tabs.first(where: { $0.id == id })?.placement != .pinned else { return }
        moveTab(id, to: .pinned)
    }

    func saveSelectedTab() {
        guard selectedSpace != nil else { return }
        let folderID = selectedSpace?.folders.first?.id
        session.moveSelectedTab(to: .saved, folderID: folderID)
        persist(scope: .core)
    }

    func saveTab(_ id: TabID) {
        let folderID = selectedSpace?.folders.first?.id
        guard let tab = selectedSpace?.tabs.first(where: { $0.id == id }),
            tab.placement != .saved || tab.folderID != folderID
        else { return }
        moveTab(id, to: .saved, folderID: folderID)
    }

    @discardableResult
    func moveTab(
        _ id: TabID,
        from sourceSpaceID: SpaceID? = nil,
        to placement: TabPlacement,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil
    ) -> Bool {
        guard let actualSourceSpaceID = session.spaceID(containing: id),
            !deletingSpaceIDs.contains(actualSourceSpaceID),
            !deletingSpaceIDs.contains(session.selectedSpaceID),
            sourceSpaceID == nil
                || sourceSpaceID == actualSourceSpaceID
        else {
            return false
        }

        let moved: Bool
        if actualSourceSpaceID == session.selectedSpaceID {
            moved = session.moveTab(
                id,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        } else {
            moved = session.moveTab(
                id,
                from: actualSourceSpaceID,
                into: session.selectedSpaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        }
        guard moved else { return false }
        if actualSourceSpaceID != session.selectedSpaceID {
            guard let destinationSpace = session.selectedSpace else { return false }
            tabDragState.relocate(
                to: BrowserSpaceRuntimeAssignment(space: destinationSpace)
            )
        }
        // A drag can cross several rows before it settles. Keep the local session
        // immediately responsive while coalescing the durable sync journal write.
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func moveTab(
        _ id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        to placement: TabPlacement,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil
    ) -> Bool {
        guard let space = space(matching: assignment),
            session.selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == id })
        else { return false }
        guard
            session.moveTab(
                id,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func moveTab(
        _ item: BrowserTabDragItem,
        to placement: TabPlacement,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil
    ) -> Bool {
        guard let destination = selectedSpace
        else { return false }
        return moveTab(
            item,
            to: placement,
            folderID: folderID,
            before: destinationTabID,
            matching: BrowserSpaceRuntimeAssignment(space: destination)
        )
    }

    @discardableResult
    func moveTab(
        _ item: BrowserTabDragItem,
        to placement: TabPlacement,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        matching destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let sourceAssignment = item.spaceAssignment
        guard let source = space(matching: sourceAssignment),
            source.tabs.contains(where: { $0.id == item.tabID }),
            let destination = space(matching: destinationAssignment),
            folderID == nil
                || destination.folders.contains(where: { $0.id == folderID }),
            destinationTabID == nil
                || destination.tabs.contains(where: {
                    $0.id == destinationTabID
                        && $0.placement == placement
                        && $0.folderID == folderID
                }),
            session.selectedSpaceID == destinationAssignment.spaceID
        else { return false }

        let moved: Bool
        if sourceAssignment == destinationAssignment {
            moved = session.moveTab(
                item.tabID,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        } else {
            moved = session.moveTab(
                item.tabID,
                from: sourceAssignment.spaceID,
                into: destinationAssignment.spaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        }
        guard moved else { return false }
        if sourceAssignment != destinationAssignment {
            tabDragState.relocate(to: destinationAssignment)
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    func canMoveTab(_ id: TabID, from sourceSpaceID: SpaceID, into destinationSpaceID: SpaceID) -> Bool {
        guard !deletingSpaceIDs.contains(sourceSpaceID),
            !deletingSpaceIDs.contains(destinationSpaceID)
        else {
            return false
        }
        return session.canMoveTab(
            id,
            from: sourceSpaceID,
            into: destinationSpaceID
        )
    }

    func canMoveTab(
        _ id: TabID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        into destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let source = space(matching: sourceAssignment),
            source.tabs.contains(where: { $0.id == id }),
            space(matching: destinationAssignment) != nil
        else { return false }
        return canMoveTab(
            id,
            from: sourceAssignment.spaceID,
            into: destinationAssignment.spaceID
        )
    }

    @discardableResult
    func moveTab(
        _ id: TabID,
        from sourceSpaceID: SpaceID,
        into destinationSpaceID: SpaceID
    ) -> Bool {
        guard !deletingSpaceIDs.contains(sourceSpaceID),
            !deletingSpaceIDs.contains(destinationSpaceID),
            session.space(id: sourceSpaceID)?.contains(id) == true,
            session.moveTab(
                id,
                from: sourceSpaceID,
                into: destinationSpaceID
            )
        else {
            return false
        }
        guard let destinationSpace = session.space(id: destinationSpaceID) else {
            return false
        }
        tabDragState.relocate(
            to: BrowserSpaceRuntimeAssignment(space: destinationSpace)
        )
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func moveTab(
        _ id: TabID,
        matching sourceAssignment: BrowserSpaceRuntimeAssignment,
        into destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard
            canMoveTab(
                id,
                matching: sourceAssignment,
                into: destinationAssignment
            )
        else { return false }
        return moveTab(
            id,
            from: sourceAssignment.spaceID,
            into: destinationAssignment.spaceID
        )
    }

    @discardableResult
    func moveTab(
        _ item: BrowserTabDragItem,
        into destinationAssignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        moveTab(
            item.tabID,
            matching: BrowserSpaceRuntimeAssignment(
                spaceID: item.spaceID,
                profileID: item.profileID
            ),
            into: destinationAssignment
        )
    }

    @discardableResult
    func duplicateTab(_ id: TabID, in spaceID: SpaceID) -> TabID? {
        guard let duplicateID = session.duplicateTab(id, in: spaceID) else { return nil }
        persist(scope: .favicon(for: duplicateID))
        return duplicateID
    }

    @discardableResult
    func duplicateTab(
        _ id: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> TabID? {
        guard let space = space(matching: assignment),
            space.tabs.contains(where: { $0.id == id })
        else { return nil }
        return duplicateTab(id, in: assignment.spaceID)
    }

    @discardableResult
    func duplicateSelectedTab() -> TabID? {
        guard let spaceID = selectedSpace?.id,
            let tab = selectedTab,
            !tab.isStartPage
        else { return nil }
        return duplicateTab(tab.id, in: spaceID)
    }

}
