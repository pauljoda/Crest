import Foundation

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
