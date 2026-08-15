import Foundation

extension BrowserSession {
    /// Joins `tabID` to the split group that `targetTabID` belongs to, creating
    /// the group when the target has none.
    ///
    /// Placement is routed entirely through `moveTab` and its
    /// `BrowserTabPlacementPlan`, so a pinned joiner leaves the pinned section
    /// by requesting the group's own placement rather than by array surgery.
    /// `memberIndex` is the slot the joiner takes inside the run; `nil` appends
    /// it after the last member. The joined tab becomes the Space's selection
    /// because every caller — drag-to-split, the tab context menu, the link
    /// menu — hands focus to the tab the person just added.
    ///
    /// Every member, the target included, has `positionModifiedAt` refreshed.
    /// Membership rides the `latestPosition` win-set in sync, so an assignment
    /// that carried a stale position timestamp would lose the merge and be
    /// undone by another device.
    @discardableResult
    mutating func addTabToSplit(
        _ tabID: TabID,
        joining targetTabID: TabID,
        at memberIndex: Int?,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard tabID != targetTabID,
            spaceID == selectedSpaceID,
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            spaces[spaceIndex].contains(tabID),
            let targetIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == targetTabID
            })
        else { return false }

        let tabs = spaces[spaceIndex].tabs
        let target = tabs[targetIndex]
        guard BrowserSplitGroupPolicy.allowsMembership(placement: target.placement) else {
            return false
        }

        let runRange = splitRunRange(containing: targetIndex, in: tabs)
        let members = runRange.map { tabs[$0] }.filter { $0.id != tabID }
        guard members.count < BrowserSplitGroupPolicy.maximumMembers else { return false }

        let slot = memberIndex.map { min(max($0, 0), members.count) } ?? members.count
        let anchorTabID: TabID?
        if slot < members.count {
            anchorTabID = members[slot].id
        } else {
            // Appending after the run anchors on whatever follows it. A `nil`
            // anchor lands at the end of the destination section, which is the
            // right answer exactly when the run ends that section.
            anchorTabID = tabs[runRange.upperBound...].first { $0.id != tabID }?.id
        }

        moveTab(
            tabID,
            to: target.placement,
            folderID: target.folderID,
            before: anchorTabID,
            at: date
        )
        guard let joinerIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            spaces[spaceIndex].tabs[joinerIndex].placement == target.placement,
            spaces[spaceIndex].tabs[joinerIndex].folderID == target.folderID
        else { return false }

        let resolvedGroupID = target.splitGroupID ?? SplitGroupID()
        let assignedIDs = Set(members.map(\.id)).union([tabID])
        for index in spaces[spaceIndex].tabs.indices {
            guard assignedIDs.contains(spaces[spaceIndex].tabs[index].id) else { continue }
            spaces[spaceIndex].tabs[index].splitGroupID = resolvedGroupID
            spaces[spaceIndex].tabs[index].markPositionModified(at: date)
        }
        spaces[spaceIndex].selectedTabID = tabID
        normalizeSplitGroupsAfterUserMutation(in: spaceID, at: date)
        return true
    }

    /// Drops one tab out of its split group and leaves it as an ordinary
    /// sibling row directly after the members it left behind.
    ///
    /// Clearing the field where the tab stands would strand the survivors on
    /// either side of a non-member, and a run broken in the middle is a
    /// dissolved run — removing one card from a three-card split would take the
    /// whole split with it. The departing tab therefore slides past the run's
    /// last member first, through the same `moveTab` placement plan every other
    /// move uses.
    ///
    /// Two cases need no move: the tab is already the run's last member, or the
    /// group is down to two and the survivor rule is about to dissolve it
    /// anyway. Relocating in either case would reorder the list for nothing.
    @discardableResult
    mutating func removeTabFromSplit(
        _ tabID: TabID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard spaceID == selectedSpaceID,
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            spaces[spaceIndex].tabs[tabIndex].splitGroupID != nil
        else { return false }

        let tabs = spaces[spaceIndex].tabs
        let runRange = splitRunRange(containing: tabIndex, in: tabs)
        let survivorCount = runRange.count - 1
        let isRunTail = tabIndex == tabs.index(before: runRange.upperBound)
        if survivorCount >= BrowserSplitGroupPolicy.minimumRenderableMembers, !isRunTail {
            let departing = tabs[tabIndex]
            // A `nil` anchor, or one that belongs to a later section, both land
            // the tab at the end of its own section — which is exactly past the
            // run whenever the run ends that section.
            moveTab(
                tabID,
                to: departing.placement,
                folderID: departing.folderID,
                before: tabs[runRange.upperBound...].first?.id,
                at: date
            )
        }

        guard
            let departedIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == tabID
            })
        else { return false }
        spaces[spaceIndex].tabs[departedIndex].splitGroupID = nil
        spaces[spaceIndex].tabs[departedIndex].markPositionModified(at: date)
        normalizeSplitGroupsAfterUserMutation(in: spaceID, at: date)
        return true
    }

    /// Relocates one card to `memberIndex` inside its own split run, leaving
    /// every tab outside the run exactly where it was.
    ///
    /// This is the primitive every reordering affordance lands on — the
    /// keyboard and menu steps below, and the card drag that hands over an
    /// arbitrary slot. `memberIndex` is clamped into the run rather than
    /// refused, because a drag reports the gap the pointer is nearest and the
    /// gaps past either end are still that end.
    ///
    /// Deliberately *not* routed through `moveTab`, unlike every other mutation
    /// in this file. Those move a tab between sections, which is the question
    /// `BrowserTabPlacementPlan` exists to answer; this one cannot leave the run
    /// it starts in, and a run is uniform in placement and folder by
    /// construction. Asking the plan where the tab belongs would mean rebuilding
    /// the answer from an anchor, and the anchor vocabulary does not fit: `nil`
    /// means "end of the section", which is only the end of the run when the run
    /// happens to end the section. Permuting the run's own slice says what is
    /// meant, keeps contiguity true by construction, and cannot disturb a
    /// neighbouring group.
    ///
    /// Selection is untouched. Reordering the cards does not change which one
    /// the chrome speaks for, and the moved card is usually the focused one
    /// already.
    @discardableResult
    mutating func moveSplitMember(
        _ tabID: TabID,
        toMemberIndex memberIndex: Int,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard spaceID == selectedSpaceID,
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            // A sub-renderable run answers `nil` here: it presents as a plain
            // tab, and a card nobody can see is a card nobody can reorder.
            spaces[spaceIndex].splitGroup(containing: tabID) != nil,
            let sourceIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == tabID
            })
        else { return false }

        let runRange = splitRunRange(
            containing: sourceIndex,
            in: spaces[spaceIndex].tabs
        )
        let sourceMemberIndex = sourceIndex - runRange.lowerBound
        let destinationMemberIndex = min(
            max(memberIndex, 0),
            runRange.count - 1
        )
        guard destinationMemberIndex != sourceMemberIndex else { return false }

        var run = Array(spaces[spaceIndex].tabs[runRange])
        run.insert(run.remove(at: sourceMemberIndex), at: destinationMemberIndex)
        // Order rides the `latestPosition` win-set in sync, so every card whose
        // slot actually changed needs a fresh stamp — the moved one and each
        // sibling the shift pushed past it. Cards outside that span kept their
        // slot and must keep their timestamp, or an untouched card would win a
        // merge it had no opinion about.
        let firstShifted = min(sourceMemberIndex, destinationMemberIndex)
        let lastShifted = max(sourceMemberIndex, destinationMemberIndex)
        for index in firstShifted...lastShifted {
            run[index].markPositionModified(at: date)
        }
        spaces[spaceIndex].tabs.replaceSubrange(runRange, with: run)
        // The permutation cannot break contiguity, uniformity, or the cap, so
        // the plain normalizer has nothing to clear here. It runs anyway because
        // every mutation leaves the Space repaired, and it never reorders.
        spaces[spaceIndex].tabs = BrowserSplitGroupNormalizer.normalized(
            spaces[spaceIndex].tabs
        )
        return true
    }

    /// Steps one card `offset` slots along its run: the "move left" and "move
    /// right" affordances, in member order.
    ///
    /// Refuses at the ends rather than wrapping. A wrapped step would send the
    /// first card to the far side of the split, which reads as a shuffle rather
    /// than a nudge, and the `false` is what lets a menu item and a menu-bar
    /// command dim themselves at the edges.
    @discardableResult
    mutating func moveSplitMember(
        _ tabID: TabID,
        by offset: Int,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard offset != 0,
            let space = space(id: spaceID),
            let groupID = space.splitGroup(containing: tabID)
        else { return false }
        let members = space.splitGroupMembers(of: groupID)
        guard let memberIndex = members.firstIndex(where: { $0.id == tabID })
        else { return false }
        let destinationMemberIndex = memberIndex + offset
        guard members.indices.contains(destinationMemberIndex) else {
            return false
        }
        return moveSplitMember(
            tabID,
            toMemberIndex: destinationMemberIndex,
            in: spaceID,
            at: date
        )
    }

    /// "Separate All Tabs": every member of the group becomes a plain tab in
    /// place, keeping its order.
    @discardableResult
    mutating func dissolveSplit(
        _ groupID: SplitGroupID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else {
            return false
        }
        var didClear = false
        for index in spaces[spaceIndex].tabs.indices {
            guard spaces[spaceIndex].tabs[index].splitGroupID == groupID else { continue }
            spaces[spaceIndex].tabs[index].splitGroupID = nil
            spaces[spaceIndex].tabs[index].markPositionModified(at: date)
            didClear = true
        }
        guard didClear else { return false }
        normalizeSplitGroupsAfterUserMutation(in: spaceID, at: date)
        return true
    }

    /// Moves a whole group to a new placement, folder, or anchor as one
    /// ordered block.
    ///
    /// Membership comes off for the duration of the move on purpose:
    /// `moveTab` normalizes after every step, and a half-relocated run is
    /// exactly the discontiguous, non-uniform shape normalization exists to
    /// clear. Each member is then inserted before the same anchor in member
    /// order, which reproduces the block whether the anchor is a tab or the
    /// end of the destination section.
    @discardableResult
    mutating func moveSplitGroup(
        _ groupID: SplitGroupID,
        to placement: TabPlacement,
        folderID requestedFolderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard spaceID == selectedSpaceID,
            BrowserSplitGroupPolicy.allowsMembership(placement: placement),
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else { return false }

        let memberIDs = spaces[spaceIndex].splitGroupMembers(of: groupID).map(\.id)
        guard !memberIDs.isEmpty else { return false }
        let memberIDSet = Set(memberIDs)
        if let destinationTabID, memberIDSet.contains(destinationTabID) { return false }

        for index in spaces[spaceIndex].tabs.indices {
            guard memberIDSet.contains(spaces[spaceIndex].tabs[index].id) else { continue }
            spaces[spaceIndex].tabs[index].splitGroupID = nil
        }
        for memberID in memberIDs {
            moveTab(
                memberID,
                to: placement,
                folderID: requestedFolderID,
                before: destinationTabID,
                at: date
            )
        }
        for index in spaces[spaceIndex].tabs.indices {
            guard memberIDSet.contains(spaces[spaceIndex].tabs[index].id) else { continue }
            spaces[spaceIndex].tabs[index].splitGroupID = groupID
            spaces[spaceIndex].tabs[index].markPositionModified(at: date)
        }
        normalizeSplitGroupsAfterUserMutation(in: spaceID, at: date)
        return true
    }

    /// Runs `BrowserSplitGroupNormalizer` and then dissolves any run left with
    /// a single member, refreshing `positionModifiedAt` on whatever it clears.
    ///
    /// Only explicit user mutations may call this. The normalizer itself keeps
    /// lone members deliberately, because a device that materializes 1-of-3
    /// synced members first must not strip and re-upload that membership; a
    /// person closing a split down to one tab is the opposite situation, and
    /// leaving a phantom one-card group behind would be the bug.
    mutating func normalizeSplitGroupsAfterUserMutation(
        in spaceID: SpaceID,
        at date: Date = .now
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        var tabs = BrowserSplitGroupNormalizer.normalized(spaces[spaceIndex].tabs)
        var memberCounts: [SplitGroupID: Int] = [:]
        for tab in tabs {
            guard let groupID = tab.splitGroupID else { continue }
            memberCounts[groupID, default: 0] += 1
        }
        for index in tabs.indices {
            guard let groupID = tabs[index].splitGroupID,
                memberCounts[groupID, default: 0]
                    < BrowserSplitGroupPolicy.minimumRenderableMembers
            else { continue }
            tabs[index].splitGroupID = nil
            tabs[index].markPositionModified(at: date)
        }
        spaces[spaceIndex].tabs = tabs
    }

    /// The contiguous run of same-group tabs around `index`, or just that one
    /// index when the tab carries no group.
    private func splitRunRange(
        containing index: Int,
        in tabs: [BrowserTab]
    ) -> Range<Int> {
        guard let groupID = tabs[index].splitGroupID else {
            return index..<tabs.index(after: index)
        }
        var start = index
        while start > tabs.startIndex, tabs[start - 1].splitGroupID == groupID {
            start -= 1
        }
        var end = tabs.index(after: index)
        while end < tabs.endIndex, tabs[end].splitGroupID == groupID {
            end += 1
        }
        return start..<end
    }
}
