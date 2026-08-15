import Foundation

extension BrowserSession {
    @discardableResult
    mutating func setExtensionTabPinned(
        _ pinned: Bool,
        tabID: TabID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
              let sourceIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }
        let wasPinned = spaces[spaceIndex].tabs[sourceIndex].placement != .current
        guard wasPinned != pinned else { return true }
        if pinned,
           spaces[spaceIndex].pinnedTabs.count >= BrowserSpace.maximumPinnedTabs {
            return false
        }
        var tab = spaces[spaceIndex].tabs.remove(at: sourceIndex)
        tab.placement = pinned ? .pinned : .current
        tab.folderID = nil
        // A pinned tab never takes part in a split. The normalizer below would
        // clear this anyway; doing it at the mutation keeps the outcome
        // deterministic rather than dependent on repair order.
        if pinned { tab.splitGroupID = nil }
        tab.savedURL = pinned ? (tab.savedURL ?? tab.url) : nil
        tab.markPositionModified(at: date)
        let insertionIndex: Int
        if pinned {
            insertionIndex = spaces[spaceIndex].tabs.firstIndex {
                $0.placement != .pinned
            } ?? spaces[spaceIndex].tabs.endIndex
        } else {
            insertionIndex = spaces[spaceIndex].tabs.firstIndex {
                $0.placement == .current
            } ?? spaces[spaceIndex].tabs.endIndex
        }
        spaces[spaceIndex].tabs.insert(tab, at: insertionIndex)
        spaces[spaceIndex].tabs = BrowserSplitGroupNormalizer.normalized(
            spaces[spaceIndex].tabs
        )
        return true
    }

    mutating func moveSelectedTab(to placement: TabPlacement, folderID: FolderID? = nil) {
        guard let selectedTabID = selectedSpace?.selectedTabID else { return }
        moveTab(selectedTabID, to: placement, folderID: folderID)
    }

    @discardableResult
    mutating func moveTab(
        _ tabID: TabID,
        to placement: TabPlacement,
        folderID requestedFolderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = selectedSpaceIndex,
              let sourceIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else {
            return false
        }
        let originalTabs = spaces[spaceIndex].tabs
        var destinationTabs = originalTabs
        let source = destinationTabs.remove(at: sourceIndex)
        guard let plan = BrowserTabPlacementPlan(
            moving: source,
            to: placement,
            folderID: requestedFolderID,
            before: destinationTabID,
            in: spaces[spaceIndex],
            among: destinationTabs
        ) else {
            return false
        }

        let movedTab = plan.placing(source)
        destinationTabs.insert(movedTab, at: plan.insertionIndex)
        guard destinationTabs != originalTabs else { return false }
        guard let movedIndex = destinationTabs.firstIndex(where: {
            $0.id == tabID
        }) else { return false }
        destinationTabs[movedIndex].markPositionModified(at: date)
        // A move can land a tab in the middle of a split run, or carry a member
        // out of one. Repair the affected Space before anyone reads it; the
        // plain normalizer only clears membership, never reorders.
        spaces[spaceIndex].tabs = BrowserSplitGroupNormalizer.normalized(destinationTabs)
        return true
    }

    func canMoveTab(
        _ tabID: TabID,
        from sourceSpaceID: SpaceID,
        into destinationSpaceID: SpaceID,
        to requestedPlacement: TabPlacement? = nil
    ) -> Bool {
        guard sourceSpaceID != destinationSpaceID,
              let source = space(id: sourceSpaceID),
              let tab = source.tabs.first(where: { $0.id == tabID }),
              let destination = space(id: destinationSpaceID) else {
            return false
        }
        return BrowserTabPlacementPlan(
            moving: tab,
            to: requestedPlacement,
            in: destination,
            among: destination.tabs
        ) != nil
    }

    /// Moves durable tab metadata across profile boundaries. The live WebKit page is
    /// deliberately not part of this operation; page pools observe the changed runtime
    /// assignment and rebuild the tab with the destination Space's website data store.
    @discardableResult
    mutating func moveTab(
        _ tabID: TabID,
        from sourceSpaceID: SpaceID,
        into destinationSpaceID: SpaceID,
        to requestedPlacement: TabPlacement? = nil,
        folderID requestedFolderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        at date: Date = .now
    ) -> Bool {
        guard sourceSpaceID != destinationSpaceID,
              let sourceSpaceIndex = spaces.firstIndex(where: { $0.id == sourceSpaceID }),
              let destinationSpaceIndex = spaces.firstIndex(where: { $0.id == destinationSpaceID }),
              let sourceTabIndex = spaces[sourceSpaceIndex].tabs.firstIndex(where: {
                  $0.id == tabID
              }) else {
            return false
        }

        let sourceTab = spaces[sourceSpaceIndex].tabs[sourceTabIndex]
        let destinationSpace = spaces[destinationSpaceIndex]
        guard let plan = BrowserTabPlacementPlan(
            moving: sourceTab,
            to: requestedPlacement,
            folderID: requestedFolderID,
            before: destinationTabID,
            in: destinationSpace,
            among: destinationSpace.tabs
        ) else {
            return false
        }

        let sourceWasSelected = spaces[sourceSpaceIndex].selectedTabID == tabID
        spaces[sourceSpaceIndex].tabs.remove(at: sourceTabIndex)
        var movedTab = plan.placing(sourceTab)
        // Split groups never span Spaces, so a tab leaving one leaves its group
        // behind rather than dragging the membership into the destination.
        movedTab.splitGroupID = nil
        movedTab.lastActivatedAt = date
        movedTab.markPositionModified(at: date)
        spaces[destinationSpaceIndex].tabs.insert(movedTab, at: plan.insertionIndex)
        spaces[sourceSpaceIndex].tabs = BrowserSplitGroupNormalizer.normalized(
            spaces[sourceSpaceIndex].tabs
        )
        spaces[destinationSpaceIndex].tabs = BrowserSplitGroupNormalizer.normalized(
            spaces[destinationSpaceIndex].tabs
        )
        if sourceWasSelected {
            spaces[sourceSpaceIndex].selectedTabID = nil
            ensureSelection(in: sourceSpaceID)
        }
        spaces[destinationSpaceIndex].selectedTabID = movedTab.id
        selectedSpaceID = destinationSpaceID
        return true
    }
}
