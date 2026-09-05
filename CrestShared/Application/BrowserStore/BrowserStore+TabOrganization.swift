import Foundation

// MARK: - Organization

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
        let folderID = selectedSpace?.folders.first { $0.location == .saved }?.id
        session.moveSelectedTab(to: .saved, folderID: folderID)
        persist(scope: .core)
    }

    func saveTab(_ id: TabID) {
        let folderID = selectedSpace?.folders.first { $0.location == .saved }?.id
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

// MARK: - Split Groups

extension BrowserStore {
    /// Joins a dragged tab to the split group `targetTabID` belongs to.
    ///
    /// The destination is the item's own Space: a split never spans Spaces, so
    /// a drag that started in another Space is refused outright rather than
    /// quietly relocating the tab first.
    @discardableResult
    func addTabToSplit(
        _ item: BrowserTabDragItem,
        joining targetTabID: TabID,
        at memberIndex: Int?
    ) -> Bool {
        guard !deletingSpaceIDs.contains(item.spaceID),
            item.spaceID == session.selectedSpaceID,
            let space = space(matching: item.spaceAssignment),
            space.tabs.contains(where: { $0.id == item.tabID }),
            space.tabs.contains(where: { $0.id == targetTabID }),
            session.addTabToSplit(
                item.tabID,
                joining: targetTabID,
                at: memberIndex,
                in: item.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    /// Removal relocates the departing tab past its run, so it goes through the
    /// same selected-Space requirement every other placement move has.
    @discardableResult
    func removeTabFromSplit(
        _ tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            session.selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == tabID }),
            session.removeTabFromSplit(tabID, in: assignment.spaceID)
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    /// Drops a card into an explicit slot of its own split run.
    ///
    /// The index is the one the domain clamps, so a drag may hand over whatever
    /// gap the pointer is nearest without checking the ends first.
    @discardableResult
    func moveSplitMember(
        _ tabID: TabID,
        toMemberIndex memberIndex: Int,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            session.selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == tabID }),
            session.moveSplitMember(
                tabID,
                toMemberIndex: memberIndex,
                in: assignment.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    /// Steps a card one or more slots along its run. Selection is untouched:
    /// the card the person is moving is the card they keep looking at.
    @discardableResult
    func moveSplitMember(
        _ tabID: TabID,
        by offset: Int,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            session.selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == tabID }),
            session.moveSplitMember(tabID, by: offset, in: assignment.spaceID)
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    /// Whether stepping `tabID` `offset` slots would move anything.
    ///
    /// One predicate for every surface that offers the move: the menu-bar items,
    /// the iPad chords, and both context menus dim themselves with this rather
    /// than each deriving "is there a card that way" for itself. A tab outside a
    /// renderable group answers `false`, so a run too short to draw offers no
    /// reordering either.
    func canMoveSplitMember(
        _ tabID: TabID,
        by offset: Int,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard offset != 0,
            session.selectedSpaceID == assignment.spaceID,
            let space = space(matching: assignment),
            let groupID = space.splitGroup(containing: tabID)
        else { return false }
        let members = space.splitGroupMembers(of: groupID)
        guard let memberIndex = members.firstIndex(where: { $0.id == tabID })
        else { return false }
        return members.indices.contains(memberIndex + offset)
    }

    @discardableResult
    func dissolveSplit(
        containing tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            let groupID = space.tabs.first(where: { $0.id == tabID })?.splitGroupID,
            session.dissolveSplit(groupID, in: assignment.spaceID)
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setSplitGroupTitle(
        _ title: String?,
        groupID: SplitGroupID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard
            space(matching: assignment)?.liveSplitGroupIDs.contains(groupID)
                == true,
            session.setSplitGroupTitle(
                title,
                groupID: groupID,
                in: assignment.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setSplitGroupEmojiIcon(
        _ emoji: String?,
        groupID: SplitGroupID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard
            space(matching: assignment)?.liveSplitGroupIDs.contains(groupID)
                == true,
            session.setSplitGroupEmojiIcon(
                emoji,
                groupID: groupID,
                in: assignment.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    @discardableResult
    func setSplitGroupTint(
        _ tint: BrowserSpaceBrandColor?,
        groupID: SplitGroupID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard
            space(matching: assignment)?.liveSplitGroupIDs.contains(groupID)
                == true,
            session.setSplitGroupTint(
                tint,
                groupID: groupID,
                in: assignment.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }

    /// The selected tab, when it can host a split card at all.
    ///
    /// Pinned tabs never take part in a split, and a Start Page is an
    /// uncommitted navigation draft that the sidebar does not even list — a
    /// group whose head is invisible in the tab list is a group nobody can
    /// manage, so neither may anchor one.
    private var splitTargetTab: BrowserTab? {
        guard let space = selectedSpace,
            let selectedTabID = space.selectedTabID,
            let selected = space.tabs.first(where: { $0.id == selectedTabID }),
            BrowserSplitGroupPolicy.allowsMembership(placement: selected.placement),
            !selected.isStartPage
        else { return nil }
        let memberCount =
            selected.splitGroupID
            .map { space.splitGroupMembers(of: $0).count } ?? 1
        guard memberCount < BrowserSplitGroupPolicy.maximumMembers else {
            return nil
        }
        return selected
    }

    /// The tab "Split With Next Tab" would add: the first tab after the
    /// selected one in its own sidebar section that is free to join.
    ///
    /// Scope is the selected tab's placement and folder, in session order,
    /// which is exactly the order that section renders in. Tabs already
    /// carrying a group are skipped rather than stolen — including the selected
    /// tab's own siblings, so repeating the command grows the group outward
    /// instead of shuffling its members.
    var nextSplitJoinCandidate: BrowserTab? {
        guard let space = selectedSpace,
            let selected = splitTargetTab,
            let selectedIndex = space.tabs.firstIndex(where: { $0.id == selected.id })
        else { return nil }
        return space.tabs[space.tabs.index(after: selectedIndex)...].first {
            $0.placement == selected.placement
                && $0.folderID == selected.folderID
                && $0.splitGroupID == nil
                && !$0.isStartPage
        }
    }

    /// Whether the tab-list menu's "Split with Current Tab" would do anything.
    ///
    /// The joiner may be pinned or filed elsewhere: `addTabToSplit` routes it
    /// through the placement plan, so it simply lands beside the selected tab.
    /// What it may not be is the selected tab itself, a member of the group it
    /// would join, or a tab in a Space that is not the selected one.
    func canSplitTabWithSelectedTab(
        _ tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.id == session.selectedSpaceID,
            let selected = splitTargetTab,
            selected.id == space.selectedTabID,
            tabID != selected.id,
            let tab = space.tabs.first(where: { $0.id == tabID }),
            !tab.isStartPage,
            tab.splitGroupID == nil || tab.splitGroupID != selected.splitGroupID
        else { return false }
        return true
    }

    /// "Split with Current Tab": the menu's subject joins the selected tab's
    /// group and takes focus, the same way a dropped tab does.
    @discardableResult
    func splitTabWithSelectedTab(
        _ tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard canSplitTabWithSelectedTab(tabID, matching: assignment),
            let space = space(matching: assignment),
            let selectedTabID = space.selectedTabID
        else { return false }
        return addTabToSplit(
            BrowserTabDragItem(
                tabID: tabID,
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            ),
            joining: selectedTabID,
            at: nil
        )
    }

    /// "Open Link in Split View": the link opens as a new tab beside the tab it
    /// came from, and the two present as one split.
    ///
    /// The tab is created through the ordinary new-tab path so it inherits the
    /// same insertion position and selection behaviour as "open in new tab";
    /// joining it afterwards moves it the short distance to the group and
    /// leaves it focused, which is what every other creation affordance does.
    @discardableResult
    func openLinkInSplit(
        url: URL,
        joining targetTabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> TabID? {
        guard let space = space(matching: assignment),
            space.id == session.selectedSpaceID,
            space.tabs.contains(where: { $0.id == targetTabID }),
            let openedID = openNewTab(url: url, matching: assignment)
        else { return nil }
        // A refused join still leaves a perfectly good new tab behind, so the
        // caller hears about the tab either way.
        addTabToSplit(
            BrowserTabDragItem(
                tabID: openedID,
                spaceID: assignment.spaceID,
                profileID: assignment.profileID
            ),
            joining: targetTabID,
            at: nil
        )
        return openedID
    }

    /// Whether "Open Link in Split View" applies to the card presenting
    /// `tabID`.
    ///
    /// The web-content context menu asks this while AppKit holds the main
    /// thread, so it answers from state rather than starting anything. The
    /// conditions are the ones `splitTargetTab` already applies to the selected
    /// tab, asked of the right-clicked card instead: a pinned tab never joins a
    /// split, a Start Page is a draft the sidebar does not even list, and a
    /// group already at `BrowserSplitGroupPolicy.maximumMembers` takes no more
    /// cards. A refusal omits the item rather than dimming it — a menu that is
    /// rarely relevant reads better without a permanently disabled row.
    func canOpenLinkInSplit(
        joining tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.id == session.selectedSpaceID,
            let tab = space.tabs.first(where: { $0.id == tabID }),
            BrowserSplitGroupPolicy.allowsMembership(placement: tab.placement),
            !tab.isStartPage
        else { return false }
        let memberCount =
            tab.splitGroupID
            .map { space.splitGroupMembers(of: $0).count } ?? 1
        return memberCount < BrowserSplitGroupPolicy.maximumMembers
    }

    /// Split-level link operations for a page pool. The macOS web-content
    /// context menu asks `canOpenLink` while it is building itself and calls
    /// `openLink` when the person picks the item.
    var splitLinkHost: BrowserSplitLinkHost {
        BrowserSplitLinkHost(
            canOpenLink: { [weak self] tabID, assignment in
                self?.canOpenLinkInSplit(joining: tabID, matching: assignment)
                    ?? false
            },
            openLink: { [weak self] url, tabID, assignment in
                _ = self?.openLinkInSplit(
                    url: url,
                    joining: tabID,
                    matching: assignment
                )
            }
        )
    }

    /// Commits a sidebar group-row drag: the whole group moves as one ordered
    /// block to a placement, folder, and anchor.
    @discardableResult
    func moveSplitGroup(
        _ groupID: SplitGroupID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        to placement: TabPlacement,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil
    ) -> Bool {
        guard let space = space(matching: assignment),
            session.selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.splitGroupID == groupID }),
            folderID == nil || space.folders.contains(where: { $0.id == folderID }),
            destinationTabID == nil
                || space.tabs.contains(where: {
                    $0.id == destinationTabID
                        && $0.placement == placement
                        && $0.folderID == folderID
                }),
            session.moveSplitGroup(
                groupID,
                to: placement,
                folderID: folderID,
                before: destinationTabID,
                in: assignment.spaceID
            )
        else { return false }
        persist(syncUrgency: .coalesced, scope: .core)
        return true
    }
}

// MARK: - Selection

extension BrowserStore {
    func space(
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> BrowserSpace? {
        guard !deletingSpaceIDs.contains(assignment.spaceID),
            let space = session.space(id: assignment.spaceID),
            assignment.matches(space)
        else { return nil }
        return space
    }

    func selectSpace(_ id: SpaceID) {
        guard id != session.selectedSpaceID,
            !deletingSpaceIDs.contains(id),
            session.space(id: id) != nil
        else { return }
        session.selectSpace(id)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    @discardableResult
    func selectAdjacentSpace(_ direction: BrowserSpaceSwipeDirection) -> SpaceID? {
        let spaces = session.spaces.filter {
            !deletingSpaceIDs.contains($0.id)
        }
        guard spaces.count > 1,
            let currentIndex = spaces.firstIndex(where: { $0.id == session.selectedSpaceID })
        else {
            return nil
        }
        let nextIndex: Int
        switch direction {
        case .previous:
            nextIndex = (currentIndex - 1 + spaces.count) % spaces.count
        case .next:
            nextIndex = (currentIndex + 1) % spaces.count
        }
        let nextID = spaces[nextIndex].id
        selectSpace(nextID)
        return nextID
    }

    func selectTab(_ id: TabID) {
        guard selectedSpace != nil else { return }
        session.selectTab(id)
        persist(syncUrgency: .coalesced, scope: .core)
    }

    @discardableResult
    func selectDismissalFallback(afterDismissing id: TabID) -> TabID? {
        guard let space = selectedSpace else { return nil }
        let fallbackID = dismissalFallbackTabID(
            afterDismissing: id,
            in: space
        )
        if let fallbackID {
            session.selectTab(fallbackID)
        } else {
            session.clearTabSelection(in: space.id)
        }
        persist(syncUrgency: .coalesced, scope: .core)
        return fallbackID
    }

    @discardableResult
    func selectAdjacentTab(offset: Int) -> TabID? {
        guard let tabs = selectedSpace?.tabs,
            !tabs.isEmpty,
            let selectedID = selectedTab?.id,
            let selectedIndex = tabs.firstIndex(where: { $0.id == selectedID })
        else {
            return nil
        }
        let count = tabs.count
        let wrappedIndex = (selectedIndex + offset % count + count) % count
        let nextID = tabs[wrappedIndex].id
        selectTab(nextID)
        return nextID
    }

    func dismissalFallbackTabID(
        afterDismissing id: TabID,
        in space: BrowserSpace
    ) -> TabID? {
        tabSelectionHistory.fallbackTabID(
            afterDismissing: id,
            in: space.id,
            availableTabIDs: Set(space.tabs.map(\.id))
        )
    }
}
