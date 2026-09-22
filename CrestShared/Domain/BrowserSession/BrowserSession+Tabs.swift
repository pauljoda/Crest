import Foundation

// MARK: - Lifecycle

extension BrowserSession {
    @discardableResult
    mutating func openTab(
        title: String,
        url: URL?,
        nativeContent: BrowserNativeTabContent? = nil,
        symbol: String = "globe",
        at date: Date = .now
    ) -> TabID? {
        openTab(
            title: title,
            url: url,
            nativeContent: nativeContent,
            symbol: symbol,
            in: selectedSpaceID,
            placement: .current,
            requestedIndex: nil,
            shouldSelect: true,
            at: date
        )
    }

    @discardableResult
    mutating func openTab(
        title: String,
        url: URL?,
        nativeContent: BrowserNativeTabContent? = nil,
        symbol: String = "globe",
        in spaceID: SpaceID,
        placement: TabPlacement = .current,
        requestedIndex: Int? = nil,
        shouldSelect: Bool = true,
        at date: Date = .now
    ) -> TabID? {
        let tab = BrowserTab(title: title, url: url, nativeContent: nativeContent, symbol: symbol,
            placement: placement, lastActivatedAt: date)
        guard let value = BrowserCoreSessionEditing.tabValue(tab),
            let result = applyCoreEdit("tab.open", in: spaceID, arguments: [
                "tab": value, "index": requestedIndex as Any? ?? NSNull(), "select": shouldSelect
            ], at: date), let id = result.tabId else { return nil }
        return TabID(rawValue: id)
    }

    @discardableResult
    mutating func activateTab(_ tabID: TabID, in spaceID: SpaceID, at date: Date = .now) -> Bool {
        applyCoreEdit("tab.activate", in: spaceID,
            arguments: ["tabId": tabID.rawValue.uuidString], at: date) != nil
    }

    @discardableResult
    mutating func closeTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        fallbackTabID: TabID? = nil,
        at date: Date = .now
    ) -> Bool {
        applyCoreEdit("tab.close", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString,
            "fallbackTabId": fallbackTabID?.rawValue.uuidString as Any? ?? NSNull(),
            "resetArchivePlacement": true
        ], at: date) != nil
    }

    mutating func closeTab(
        _ tabID: TabID,
        fallbackTabID: TabID? = nil,
        at date: Date = .now
    ) {
        applyCoreEdit("tab.close", in: selectedSpaceID, arguments: [
            "tabId": tabID.rawValue.uuidString,
            "fallbackTabId": fallbackTabID?.rawValue.uuidString as Any? ?? NSNull()
        ], at: date)
    }

    @discardableResult
    mutating func clearCurrentTabs(
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        applyCoreEdit("tab.clear_current", in: spaceID, arguments: [:], at: date) != nil
    }

    @discardableResult
    mutating func deleteTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        applyCoreEdit("tab.delete", in: spaceID,
            arguments: ["tabId": tabID.rawValue.uuidString], at: date) != nil
    }

    @discardableResult
    mutating func duplicateTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        placement: TabPlacement = .current,
        requestedIndex: Int? = nil,
        shouldSelect: Bool = true,
        at date: Date = .now
    ) -> TabID? {
        guard let result = applyCoreEdit("tab.copy", in: spaceID, arguments: [
                "tabId": tabID.rawValue.uuidString, "ids": [UUID().uuidString], "placement": placement.rawValue,
                "index": requestedIndex as Any? ?? NSNull(), "select": shouldSelect
            ], at: date), let id = result.tabId
        else { return nil }
        return TabID(rawValue: id)
    }

}

// MARK: - Placement

extension BrowserSession {
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
        detachesFromSplit: Bool = false,
        at date: Date = .now
    ) -> Bool {
        applyCoreEdit("tab.move", in: selectedSpaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "placement": placement.rawValue,
            "folderId": requestedFolderID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": destinationTabID?.rawValue.uuidString as Any? ?? NSNull(),
            "detach": detachesFromSplit
        ], at: date)?.changed ?? false
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
            let destination = space(id: destinationSpaceID)
        else {
            return false
        }
        return (try? BrowserCoreTabTransfer.preview(source: source, destination: destination,
            arguments: BrowserCoreTabTransfer.arguments(tabID: tab.id, placement: requestedPlacement), at: .now)) != nil
    }

    /// Moves durable tab metadata across profile boundaries. The live engine page is
    /// deliberately not part of this operation; page pools observe the changed runtime
    /// assignment and rebuild the tab with the destination Space's profile.
    @discardableResult
    mutating func moveTab(
        _ tabID: TabID,
        from sourceSpaceID: SpaceID,
        into destinationSpaceID: SpaceID,
        to requestedPlacement: TabPlacement? = nil,
        folderID requestedFolderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        sourceFallbackTabID: TabID? = nil,
        at date: Date = .now
    ) -> Bool {
        guard sourceSpaceID != destinationSpaceID,
            let sourceSpaceIndex = spaces.firstIndex(where: { $0.id == sourceSpaceID }),
            let destinationSpaceIndex = spaces.firstIndex(where: { $0.id == destinationSpaceID }),
            let sourceTabIndex = spaces[sourceSpaceIndex].tabs.firstIndex(where: {
                $0.id == tabID
            })
        else {
            return false
        }

        let moved = spaces[sourceSpaceIndex].tabs[sourceTabIndex]
        do {
            let result = try BrowserCoreTabTransfer.preview(source: spaces[sourceSpaceIndex], destination: spaces[destinationSpaceIndex],
                arguments: BrowserCoreTabTransfer.arguments(tabID: tabID, placement: requestedPlacement, folderID: requestedFolderID,
                    before: destinationTabID, fallback: sourceFallbackTabID), at: date)
            let intermediate = try BrowserCoreTabTransfer.applying(result.source, to: self, moved: moved)
            self = try BrowserCoreTabTransfer.applying(result.destination, to: intermediate, moved: moved)
            return true
        } catch { return false }
    }
}

// MARK: - Appearance

/// What a page observation actually changed. The store needs the tab whose
/// stored image moved, so a title rewrite does not rewrite the favicon store.
struct BrowserTabObservation: Equatable, Sendable {
    var tabID: TabID
    var changedFavicon: Bool
}

extension BrowserSession {
    /// Records what a live page reports about itself.
    ///
    /// Which of these fields a tab accepts — whether a page may replace its
    /// icon, which address an automatic icon belongs to, whether a blank title
    /// clears the name — is one set of rules in the core. A Split View card
    /// observes its own page whether or not it is the focused one, so the
    /// unfocused path is the same call rather than a second set of rules.
    @discardableResult
    mutating func observePage(
        url: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> BrowserTabObservation? {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tab = spaces[spaceIndex].tabs.first(where: { $0.id == tabID })
        else { return nil }
        // Page observations are frequent, and a page that reports exactly what
        // the tab already stores cannot change it. This is an identity check,
        // not a rule: precedence and address normalization stay in the core,
        // which still answers for every observation that differs at all.
        guard (url ?? tab.url) != tab.url || title != tab.title
            || faviconData != tab.faviconData || iconAccent != tab.iconAccent
        else { return nil }
        let result = applyCoreEdit("tab.observe", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString,
            "url": url?.absoluteString as Any? ?? NSNull(),
            "title": title as Any? ?? NSNull(),
            "hasFavicon": !(faviconData?.isEmpty ?? true),
            "faviconChanged": faviconData != tab.faviconData,
            "iconAccent": BrowserCoreSessionEditing.value(iconAccent) ?? NSNull()
        ], at: .now)
        guard let result, result.changed else { return nil }
        let assigned = applyCoreFavicon(result.favicon, bytes: faviconData, at: spaceIndex)
        return BrowserTabObservation(tabID: assigned ?? tabID, changedFavicon: assigned != nil)
    }

    @discardableResult
    mutating func updateSelectedTab(
        url: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil
    ) -> BrowserTabObservation? {
        guard let indices = selectedTabIndices else { return nil }
        return observePage(
            url: url, title: title, faviconData: faviconData, iconAccent: iconAccent,
            tabID: spaces[indices.space].tabs[indices.tab].id, in: spaces[indices.space].id)
    }

    /// The named-tab twin of ``updateSelectedTab(url:title:faviconData:iconAccent:)``.
    @discardableResult
    mutating func updateTab(
        url: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        observePage(
            url: url, title: title, faviconData: faviconData, iconAccent: iconAccent,
            tabID: tabID, in: spaceID) != nil
    }

    /// Names a tab by hand. The observed page title keeps updating underneath,
    /// so clearing the rename returns the tab to whatever the page reports.
    @discardableResult
    mutating func setTabCustomTitle(
        _ title: String?,
        tabID: TabID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        applyCoreEdit("tab.rename", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "title": title as Any? ?? NSNull()
        ], at: date)?.changed ?? false
    }

    /// Emoji normalization stays native because it is grapheme handling; the
    /// core owns the stored vocabulary and what an icon choice clears.
    @discardableResult
    mutating func setTabEmojiIcon(
        _ emoji: String,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let normalized = BrowserIconSymbol.normalizedEmoji(emoji) else { return false }
        return setTabIcon("emoji", emoji: normalized, tabID: tabID, in: spaceID)
    }

    @discardableResult
    mutating func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        setTabIcon("pulled", faviconData: faviconData, iconAccent: iconAccent, tabID: tabID, in: spaceID)
    }

    @discardableResult
    mutating func clearTabIcon(tabID: TabID, in spaceID: SpaceID) -> Bool {
        setTabIcon("automatic", tabID: tabID, in: spaceID)
    }

    private mutating func setTabIcon(
        _ mode: String,
        emoji: String? = nil,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return false }
        var arguments: [String: Any] = [
            "tabId": tabID.rawValue.uuidString,
            "mode": mode,
            "hasFavicon": !(faviconData?.isEmpty ?? true),
            "iconAccent": BrowserCoreSessionEditing.value(iconAccent) ?? NSNull()
        ]
        if let emoji { arguments["emoji"] = emoji }
        guard let result = applyCoreEdit("tab.icon", in: spaceID, arguments: arguments, at: .now),
            result.changed
        else { return false }
        applyCoreFavicon(result.favicon, bytes: faviconData, at: spaceIndex)
        return true
    }

    /// A favicon that finished loading after the page moved on belongs to the
    /// address it was captured from, which is the core's comparison to make.
    @discardableResult
    mutating func cacheAutomaticTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        url: URL,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let result = applyCoreEdit("tab.favicon.cache", in: spaceID, arguments: [
                "tabId": tabID.rawValue.uuidString,
                "url": url.absoluteString,
                "hasFavicon": !faviconData.isEmpty,
                "iconAccent": BrowserCoreSessionEditing.value(iconAccent) ?? NSNull()
            ], at: .now),
            result.changed
        else { return false }
        applyCoreFavicon(result.favicon, bytes: faviconData, at: spaceIndex)
        return true
    }

    @discardableResult
    mutating func replaceTabSavedLocationWithCurrent(
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        applyCoreEdit("tab.saved_location", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "action": "replace"
        ], at: .now)?.changed ?? false
    }

    @discardableResult
    mutating func restoreTabSavedLocation(
        tabID: TabID,
        in spaceID: SpaceID
    ) -> URL? {
        guard let result = applyCoreEdit("tab.saved_location", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "action": "restore"
        ], at: .now), result.changed,
            let index = spaces.firstIndex(where: { $0.id == spaceID })
        else { return nil }
        return spaces[index].tabs.first { $0.id == tabID }?.url
    }
}

// MARK: - Split Groups

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
        guard spaceID == selectedSpaceID else { return false }
        return applyCoreEdit("split.join_in_place", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "targetId": targetTabID.rawValue.uuidString,
            "index": memberIndex as Any? ?? NSNull(), "groupId": UUID().uuidString
        ], at: date)?.changed ?? false
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
        guard spaceID == selectedSpaceID else { return false }
        return applyCoreEdit("split.leave", in: spaceID,
            arguments: ["tabId": tabID.rawValue.uuidString], at: date)?.changed ?? false
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
        guard spaceID == selectedSpaceID else { return false }
        return applyCoreEdit("split.reorder", in: spaceID,
            arguments: ["tabId": tabID.rawValue.uuidString, "index": memberIndex], at: date)?.changed ?? false
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
        return applyCoreEdit("split.reorder", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "offset": offset
        ], at: date)?.changed ?? false
    }

    /// "Separate All Tabs": every member of the group becomes a plain tab in
    /// place, keeping its order.
    @discardableResult
    mutating func dissolveSplit(
        _ groupID: SplitGroupID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        return applyCoreEdit("split.dissolve", in: spaceID,
            arguments: ["groupId": groupID.rawValue.uuidString], at: date)?.changed ?? false
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
        guard spaceID == selectedSpaceID else { return false }
        return applyCoreEdit("split.move", in: spaceID, arguments: [
            "groupId": groupID.rawValue.uuidString, "placement": placement.rawValue,
            "folderId": requestedFolderID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": destinationTabID?.rawValue.uuidString as Any? ?? NSNull()
        ], at: date)?.changed ?? false
    }

    @discardableResult
    mutating func setSplitGroupTitle(
        _ title: String?,
        groupID: SplitGroupID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        updateSplitGroupMetadata(groupID: groupID, in: spaceID) {
            let resolved = BrowserTab.resolvedCustomTitle(title)
            guard $0.customTitle != resolved else { return false }
            $0.setTitle(resolved, at: date)
            return true
        }
    }

    @discardableResult
    mutating func setSplitGroupEmojiIcon(
        _ emoji: String?,
        groupID: SplitGroupID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        let normalized = emoji.flatMap(BrowserIconSymbol.normalizedEmoji)
        if emoji != nil, normalized == nil { return false }
        return updateSplitGroupMetadata(groupID: groupID, in: spaceID) {
            guard $0.emojiIcon != normalized else { return false }
            $0.setEmojiIcon(normalized, at: date)
            return true
        }
    }

    @discardableResult
    mutating func setSplitGroupTint(
        _ tint: BrowserSpaceBrandColor?,
        groupID: SplitGroupID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        updateSplitGroupMetadata(groupID: groupID, in: spaceID) {
            guard $0.tint != tint else { return false }
            $0.setTint(tint, at: date)
            return true
        }
    }

    private mutating func updateSplitGroupMetadata(
        groupID: SplitGroupID,
        in spaceID: SpaceID,
        mutation: (inout BrowserSplitGroupMetadata) -> Bool
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            spaces[spaceIndex].liveSplitGroupIDs.contains(groupID)
        else { return false }
        let metadataIndex = spaces[spaceIndex].splitGroups.firstIndex {
            $0.id == groupID
        }
        var metadata =
            metadataIndex.map {
                spaces[spaceIndex].splitGroups[$0]
            } ?? BrowserSplitGroupMetadata(id: groupID)
        guard mutation(&metadata) else { return false }
        if let metadataIndex {
            spaces[spaceIndex].splitGroups[metadataIndex] = metadata
        } else {
            spaces[spaceIndex].splitGroups.append(metadata)
        }
        return true
    }

}

// MARK: - Residency

extension BrowserSession {
    @discardableResult
    mutating func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        applyCoreEdit("tab.residency", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "keep": keepsPageLoaded
        ], at: .now)?.changed ?? false
    }
}
