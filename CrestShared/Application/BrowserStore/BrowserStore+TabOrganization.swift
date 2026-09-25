import Foundation

// MARK: - Organization

extension BrowserStore {
    /// Pins the selected tab, which leaves its split: pinned tabs keep none.
    func pinSelectedTab() {
        guard let id = selectedTab?.id, let spaceID = selectedSpace?.id,
            moveSessionTab(id, in: spaceID, to: .pinned, detachesFromSplit: !TabPlacement.pinned.holdsSplits)
        else { return }
    }

    func pinTab(_ id: TabID) {
        guard selectedSpace?.tabs.first(where: { $0.id == id })?.placement != .pinned else { return }
        moveTab(id, to: .pinned)
    }

    func saveSelectedTab() {
        guard let id = selectedTab?.id, let space = selectedSpace else { return }
        let folderID = space.folders.first { $0.location == .saved }?.id
        guard moveSessionTab(id, in: space.id, to: .saved, folderID: folderID) else { return }
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
            let actualSourceSpace = session.space(id: actualSourceSpaceID),
            !deletingSpaceIDs.contains(actualSourceSpaceID),
            !deletingSpaceIDs.contains(selectedSpaceID),
            sourceSpaceID == nil
                || sourceSpaceID == actualSourceSpaceID
        else {
            return false
        }

        let moved: Bool
        if actualSourceSpaceID == selectedSpaceID {
            // A tab moving to a section that keeps no splits leaves its own.
            moved = moveSessionTab(
                id, in: actualSourceSpaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID,
                detachesFromSplit: !placement.holdsSplits
            )
        } else {
            moved = moveTabBetweenSpaces(
                id,
                from: actualSourceSpaceID,
                into: selectedSpaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID
            )
        }
        guard moved else { return false }
        if actualSourceSpaceID != selectedSpaceID {
            guard let destinationSpace = selectedSpace else { return false }
            interactionObserver?.browserDidMoveTab(
                from: BrowserTabRuntimeAssignment(
                    tabID: id, spaceID: actualSourceSpace.id, profileID: actualSourceSpace.profile.id),
                to: BrowserSpaceRuntimeAssignment(space: destinationSpace)
            )
        }
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
            selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == id })
        else { return false }
        guard
            moveSessionTab(
                id, in: assignment.spaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID,
                detachesFromSplit: !placement.holdsSplits
            )
        else { return false }
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
        matching destinationAssignment: BrowserSpaceRuntimeAssignment,
        detachesFromSplit: Bool = false
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
            selectedSpaceID == destinationAssignment.spaceID
        else { return false }

        let moved: Bool
        if sourceAssignment == destinationAssignment {
            moved = moveSessionTab(
                item.tabID, in: sourceAssignment.spaceID,
                to: placement,
                folderID: folderID,
                before: destinationTabID,
                detachesFromSplit: detachesFromSplit
            )
        } else {
            moved = moveTabBetweenSpaces(
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
            interactionObserver?.browserDidMoveTab(from: item.runtimeAssignment, to: destinationAssignment)
        }
        return true
    }

    func canMoveTab(_ id: TabID, from sourceSpaceID: SpaceID, into destinationSpaceID: SpaceID) -> Bool {
        guard !deletingSpaceIDs.contains(sourceSpaceID),
            !deletingSpaceIDs.contains(destinationSpaceID)
        else {
            return false
        }
        guard let source = session.space(id: sourceSpaceID), let destination = session.space(id: destinationSpaceID),
            source.contains(id), sourceSpaceID != destinationSpaceID
        else { return false }
        return family.canSend(
            MoveTabToSpace(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: source.id,
                tabID: id, destinationSpaceID: destination.id, placement: nil, folderID: nil,
                beforeTabID: nil, follows: false),
            from: self)
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
            let sourceSpace = session.space(id: sourceSpaceID),
            sourceSpace.contains(id),
            moveTabBetweenSpaces(
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
        interactionObserver?.browserDidMoveTab(
            from: BrowserTabRuntimeAssignment(tabID: id, spaceID: sourceSpace.id, profileID: sourceSpace.profile.id),
            to: BrowserSpaceRuntimeAssignment(space: destinationSpace)
        )
        return true
    }

    /// A followed move explicitly opens one tab in its new profile. Ordinary
    /// Space entry must still leave remembered unloaded tabs alone.
    @discardableResult
    func consumeMovedTabActivation() -> Bool {
        guard let activation = pendingMovedTabActivation else { return false }
        pendingMovedTabActivation = nil
        return selectedSpace?.id == activation.spaceID
            && selectedSpace?.profile.id == activation.profileID
            && selectedTab?.id == activation.tabID
    }

    private func moveTabBetweenSpaces(
        _ id: TabID,
        from sourceSpaceID: SpaceID,
        into destinationSpaceID: SpaceID,
        to placement: TabPlacement? = nil,
        folderID: FolderID? = nil,
        before destinationTabID: TabID? = nil
    ) -> Bool {
        guard let source = session.space(id: sourceSpaceID) else { return false }
        guard let destination = session.space(id: destinationSpaceID) else { return false }
        let follows = linkPreferences.followsTabsMovedToAnotherSpace
        do {
            try family.commit(
                MoveTabToSpace(
                    workspaceID: family.workspaceID, windowID: windowID, spaceID: source.id,
                    tabID: id, destinationSpaceID: destination.id, placement: placement,
                    folderID: folderID, beforeTabID: destinationTabID, follows: follows),
                from: self)
        } catch {
            localSyncErrorDescription = "Core tab move failed: \(error)"
            return false
        }
        if follows {
            pendingMovedTabActivation = BrowserTabRuntimeAssignment(
                tabID: id, spaceID: destination.id, profileID: destination.profile.id)
        }
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

    /// Copies a tab among the open tabs, under an identity the core gives it,
    /// and shows the copy. Answers the copy, or nil when the core refused it.
    @discardableResult
    func duplicateTab(_ id: TabID, in spaceID: SpaceID) -> TabID? {
        guard let space = session.space(id: spaceID),
            let copy = sendCopying(
                DuplicateTab(
                    workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                    tabID: id, placement: nil, shows: true),
                in: space)?.first
        else { return nil }
        return copy.copyTabID
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
            item.spaceID == selectedSpaceID,
            let space = space(matching: item.spaceAssignment),
            space.tabs.contains(where: { $0.id == item.tabID }),
            space.tabs.contains(where: { $0.id == targetTabID })
        else { return false }
        return sendCopying(
            JoinSplit(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id,
                tabID: item.tabID, targetTabID: targetTabID, index: memberIndex),
            in: space) != nil
    }

    /// Removal relocates the departing tab past its run, so it goes through the
    /// same selected-Space requirement every other placement move has.
    @discardableResult
    func removeTabFromSplit(
        _ tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == tabID })
        else { return false }
        return family.send(
            LeaveSplit(workspaceID: family.workspaceID, spaceID: space.id, tabID: tabID), from: self)
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
            selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == tabID })
        else { return false }
        return family.send(
            MoveSplitMember(
                workspaceID: family.workspaceID, spaceID: space.id, tabID: tabID, index: memberIndex),
            from: self)
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
            selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.id == tabID })
        else { return false }
        return family.send(
            StepSplitMember(
                workspaceID: family.workspaceID, spaceID: space.id, tabID: tabID, offset: offset),
            from: self)
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
            selectedSpaceID == assignment.spaceID,
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
            let groupID = space.tabs.first(where: { $0.id == tabID })?.splitGroupID
        else { return false }
        return family.send(
            DissolveSplit(workspaceID: family.workspaceID, spaceID: space.id, groupID: groupID),
            from: self)
    }

    @discardableResult
    func setSplitGroupTitle(
        _ title: String?,
        groupID: SplitGroupID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return family.send(
            NameSplit(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, groupID: groupID,
                name: title),
            from: self, failure: "Core record command failed")
    }

    @discardableResult
    func setSplitGroupEmojiIcon(
        _ emoji: String?,
        groupID: SplitGroupID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        let normalized = emoji.flatMap(BrowserIconSymbol.normalizedEmoji)
        guard emoji == nil || normalized != nil, space(matching: assignment) != nil else { return false }
        return family.send(
            SetSplitIcon(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, groupID: groupID,
                symbol: normalized.map(BrowserIconSymbol.symbol(forEmoji:))),
            from: self, failure: "Core record command failed")
    }

    @discardableResult
    func setSplitGroupTint(
        _ tint: BrowserSpaceBrandColor?,
        groupID: SplitGroupID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard space(matching: assignment) != nil else { return false }
        return family.send(
            TintSplit(
                workspaceID: family.workspaceID, spaceID: assignment.spaceID, groupID: groupID,
                tint: tint?.core),
            from: self, failure: "Core record command failed")
    }

    /// Whether the core would join `tabID` to the split of `targetTabID`: no
    /// Start Page on either side, not already one group, and room for another
    /// card. Asked without committing, so menus reflect the core's own rule.
    private func acceptsSplitJoin(_ tabID: TabID, joining targetTabID: TabID, in space: BrowserSpace) -> Bool {
        family.canSend(
            JoinSplit(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id,
                tabID: tabID, targetTabID: targetTabID, index: nil),
            from: self)
    }

    /// The tab "Split With Next Tab" would add to the split of the tab this
    /// window shows, as the core answers it: the next tab row in the shown
    /// tab's own sidebar list that is in no split, when the core would join it.
    var nextSplitJoinCandidate: TabID? {
        (try? core.query(SplitJoinCandidate(windowID: windowID)))?.tabID
    }

    /// Whether the tab-list menu's "Split with Current Tab" would do anything:
    /// the core accepts joining the menu's subject to the selected tab's group
    /// in the Space this window shows.
    func canSplitTabWithSelectedTab(
        _ tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.id == selectedSpaceID,
            let selectedTabID = selectedTabID(in: space.id),
            tabID != selectedTabID
        else { return false }
        return acceptsSplitJoin(tabID, joining: selectedTabID, in: space)
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
            let selectedTabID = selectedTabID(in: space.id)
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
    /// The core commits the new tab and any durable destination copies together
    /// after validating the complete join.
    @discardableResult
    func openLinkInSplit(
        url: URL,
        joining targetTabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> TabID? {
        guard canOpenLinkInSplit(joining: targetTabID, matching: assignment),
            let space = space(matching: assignment)
        else { return nil }
        let openedID = TabID()
        guard
            sendCopying(
                OpenLinkInSplit(
                    workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id,
                    tabID: openedID, targetTabID: targetTabID, address: url.absoluteString,
                    title: url.host() ?? url.absoluteString),
                in: space) != nil
        else { return nil }
        return openedID
    }

    /// Whether "Open Link in Split View" applies to the card presenting
    /// `tabID`.
    ///
    /// The web-content context menu asks this while AppKit holds the main
    /// thread, so it prepares the core command and releases it without
    /// starting anything: a Start Page is a draft the sidebar does not even
    /// list, and a full group takes no more cards. A refusal omits the item
    /// rather than dimming it — a menu that is rarely relevant reads better
    /// without a permanently disabled row.
    func canOpenLinkInSplit(
        joining tabID: TabID,
        matching assignment: BrowserSpaceRuntimeAssignment
    ) -> Bool {
        guard let space = space(matching: assignment),
            space.id == selectedSpaceID,
            space.contains(tabID)
        else { return false }
        return family.canSend(
            OpenLinkInSplit(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: space.id, tabID: UUID(),
                targetTabID: tabID, address: "about:blank", title: ""),
            from: self)
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
            selectedSpaceID == assignment.spaceID,
            space.tabs.contains(where: { $0.splitGroupID == groupID }),
            folderID == nil || space.folders.contains(where: { $0.id == folderID }),
            destinationTabID == nil
                || space.tabs.contains(where: {
                    $0.id == destinationTabID
                        && $0.placement == placement
                        && $0.folderID == folderID
                })
        else { return false }
        return family.send(
            MoveSplit(
                workspaceID: family.workspaceID, spaceID: space.id, groupID: groupID,
                placement: placement, folderID: folderID, beforeTabID: destinationTabID),
            from: self)
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

    /// Shows another Space in this window. What a window shows is the core
    /// device's, and never part of the session.
    func selectSpace(_ id: SpaceID) {
        guard id != selectedSpaceID,
            !deletingSpaceIDs.contains(id),
            session.space(id: id) != nil
        else { return }
        selectPresentedSpace(id)
    }

    func selectTab(_ id: TabID) {
        guard let space = selectedSpace, activateSessionTab(id, in: space.id) else { return }
    }

    /// Stops showing a tab without closing it: the window returns to the tab
    /// it showed before in the shown Space, or shows nothing there.
    func selectDismissalFallback(afterDismissing id: TabID) {
        guard let space = selectedSpace else { return }
        dismissShownTab(id, in: space.id)
    }
}
