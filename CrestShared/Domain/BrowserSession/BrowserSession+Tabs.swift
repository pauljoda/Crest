import Foundation

// MARK: - Lifecycle

extension BrowserSession {
    @discardableResult
    mutating func openTab(
        title: String,
        url: URL?,
        symbol: String = "globe",
        at date: Date = .now
    ) -> TabID? {
        openTab(
            title: title,
            url: url,
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
        symbol: String = "globe",
        in spaceID: SpaceID,
        placement: TabPlacement = .current,
        requestedIndex: Int? = nil,
        shouldSelect: Bool = true,
        at date: Date = .now
    ) -> TabID? {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else {
            return nil
        }
        if placement == .pinned,
            spaces[spaceIndex].pinnedTabs.count >= BrowserSpace.maximumPinnedTabs
        {
            return nil
        }
        let tab = BrowserTab(
            title: title,
            url: url,
            symbol: symbol,
            placement: placement,
            lastActivatedAt: date
        )
        let tabs = spaces[spaceIndex].tabs
        let placementRange: Range<Int> =
            switch placement {
            case .pinned:
                0..<(tabs.firstIndex { $0.placement != .pinned } ?? tabs.endIndex)
            case .saved:
                (tabs.firstIndex { $0.placement == .saved }
                    ?? tabs.firstIndex { $0.placement == .current }
                    ?? tabs.endIndex)..<(tabs.firstIndex { $0.placement == .current }
                    ?? tabs.endIndex)
            case .current:
                (tabs.firstIndex { $0.placement == .current } ?? tabs.endIndex)..<tabs.endIndex
            }
        let insertionIndex: Int
        if let requestedIndex {
            insertionIndex = min(
                max(requestedIndex, placementRange.lowerBound),
                placementRange.upperBound
            )
        } else {
            insertionIndex =
                switch placement {
                case .pinned, .saved:
                    placementRange.upperBound
                case .current:
                    placementRange.lowerBound
                }
        }
        spaces[spaceIndex].tabs.insert(tab, at: insertionIndex)
        if shouldSelect {
            selectedSpaceID = spaceID
            spaces[spaceIndex].selectedTabID = tab.id
        }
        return tab.id
    }

    @discardableResult
    mutating func activateTab(_ tabID: TabID, in spaceID: SpaceID, at date: Date = .now) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        selectedSpaceID = spaceID
        spaces[spaceIndex].tabs[tabIndex].lastActivatedAt = date
        spaces[spaceIndex].selectedTabID = tabID
        return true
    }

    @discardableResult
    mutating func closeExtensionTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        fallbackTabID: TabID? = nil,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == tabID && $0.placement == .current
            })
        else {
            return false
        }
        let wasSelected = spaces[spaceIndex].selectedTabID == tabID
        preserveFolderOrder(in: spaceIndex, removing: [tabID])
        var tab = spaces[spaceIndex].tabs.remove(at: tabIndex)
        tab.placement = .current
        tab.folderID = nil
        tab.splitGroupID = nil
        tab.savedURL = nil
        tab.faviconData = nil
        if !tab.isStartPage {
            spaces[spaceIndex].archivedTabs.append(
                ArchivedTab(tab: tab, archivedAt: date, reason: .closed)
            )
        }
        if wasSelected {
            spaces[spaceIndex].selectedTabID = fallbackTabID.flatMap { candidate in
                spaces[spaceIndex].contains(candidate) ? candidate : nil
            }
        }
        normalizeSplitGroupsAfterUserMutation(in: spaceID, at: date)
        return true
    }

    @discardableResult
    mutating func updateExtensionTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        url: URL
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        spaces[spaceIndex].tabs[tabIndex].url = url
        spaces[spaceIndex].tabs[tabIndex].title = url.host() ?? url.absoluteString
        return true
    }

    mutating func closeTab(
        _ tabID: TabID,
        fallbackTabID: TabID? = nil,
        at date: Date = .now
    ) {
        guard let spaceIndex = selectedSpaceIndex else { return }
        guard
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == tabID && $0.placement == .current
            })
        else { return }
        let wasSelected = spaces[spaceIndex].selectedTabID == tabID
        preserveFolderOrder(in: spaceIndex, removing: [tabID])
        var tab = spaces[spaceIndex].tabs.remove(at: tabIndex)
        tab.faviconData = nil
        tab.splitGroupID = nil
        if !tab.isStartPage {
            spaces[spaceIndex].archivedTabs.append(
                ArchivedTab(tab: tab, archivedAt: date, reason: .closed)
            )
        }
        if wasSelected {
            spaces[spaceIndex].selectedTabID = fallbackTabID.flatMap { candidate in
                spaces[spaceIndex].contains(candidate) ? candidate : nil
            }
        }
        // Closing a card is how a split shrinks. A group left with one member
        // dissolves here, at the explicit user mutation, and nowhere else.
        normalizeSplitGroupsAfterUserMutation(in: spaces[spaceIndex].id, at: date)
    }

    @discardableResult
    mutating func clearCurrentTabs(
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else { return false }

        let currentTabs = spaces[spaceIndex].tabs.filter {
            $0.placement == .current
        }
        guard !currentTabs.isEmpty else { return false }

        spaces[spaceIndex].archivedTabs.append(
            contentsOf: currentTabs.compactMap { source in
                guard !source.isStartPage else { return nil }
                var tab = source
                tab.faviconData = nil
                tab.splitGroupID = nil
                return ArchivedTab(
                    tab: tab,
                    archivedAt: date,
                    reason: .closed
                )
            }
        )
        let currentTabIDs = Set(currentTabs.map(\.id))
        preserveFolderOrder(in: spaceIndex, removing: currentTabIDs)
        spaces[spaceIndex].tabs.removeAll { currentTabIDs.contains($0.id) }
        ensureSelection(in: spaceID)
        normalizeSplitGroupsAfterUserMutation(in: spaceID, at: date)
        return true
    }

    @discardableResult
    mutating func deleteTab(
        _ tabID: TabID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        let wasSelected = spaces[spaceIndex].selectedTabID == tabID
        preserveFolderOrder(in: spaceIndex, removing: [tabID])
        var tab = spaces[spaceIndex].tabs.remove(at: tabIndex)
        tab.placement = .current
        tab.folderID = nil
        tab.splitGroupID = nil
        tab.savedURL = nil
        tab.faviconData = nil
        if !tab.isStartPage {
            spaces[spaceIndex].archivedTabs.append(
                ArchivedTab(tab: tab, archivedAt: date, reason: .deleted)
            )
        }
        if wasSelected {
            spaces[spaceIndex].selectedTabID = nil
        }
        ensureSelection(in: spaceID)
        normalizeSplitGroupsAfterUserMutation(in: spaceID, at: date)
        return true
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
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let source = spaces[spaceIndex].tabs.first(where: { $0.id == tabID })
        else {
            return nil
        }
        if placement == .pinned,
            spaces[spaceIndex].pinnedTabs.count >= BrowserSpace.maximumPinnedTabs
        {
            return nil
        }
        let duplicate = BrowserTab(
            title: source.title,
            url: source.url,
            symbol: source.symbol,
            faviconData: source.faviconData,
            faviconURL: source.faviconURL,
            iconAccent: source.iconAccent,
            iconMode: source.iconMode,
            placement: placement,
            lastActivatedAt: date,
            customTitle: source.customTitle,
            titleModifiedAt: source.customTitle == nil ? nil : date
        )
        let tabs = spaces[spaceIndex].tabs
        let placementLowerBound: Int =
            switch placement {
            case .pinned:
                0
            case .saved:
                tabs.firstIndex { $0.placement == .saved }
                    ?? tabs.firstIndex { $0.placement == .current }
                    ?? tabs.endIndex
            case .current:
                tabs.firstIndex { $0.placement == .current }
                    ?? tabs.endIndex
            }
        let placementUpperBound: Int =
            switch placement {
            case .pinned:
                tabs.firstIndex { $0.placement != .pinned }
                    ?? tabs.endIndex
            case .saved:
                tabs.firstIndex { $0.placement == .current }
                    ?? tabs.endIndex
            case .current:
                tabs.endIndex
            }
        let insertionIndex =
            requestedIndex.map {
                min(max($0, placementLowerBound), placementUpperBound)
            } ?? placementLowerBound
        spaces[spaceIndex].tabs.insert(duplicate, at: insertionIndex)
        if shouldSelect {
            spaces[spaceIndex].selectedTabID = duplicate.id
            selectedSpaceID = spaceID
        }
        return duplicate.id
    }

}

// MARK: - Placement

extension BrowserSession {
    @discardableResult
    mutating func setExtensionTabPinned(
        _ pinned: Bool,
        tabID: TabID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let sourceIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        // Only the pinned strip counts as pinned. A saved tab is neither
        // pinned nor current, so pinning it moves it into the strip the way
        // Crest's own Pin Tab action does, and unpinning it is a no-op rather
        // than a move out of the saved list.
        let wasPinned = spaces[spaceIndex].tabs[sourceIndex].placement == .pinned
        guard wasPinned != pinned else { return true }
        if pinned,
            spaces[spaceIndex].pinnedTabs.count >= BrowserSpace.maximumPinnedTabs
        {
            return false
        }
        preserveFolderOrder(in: spaceIndex, removing: [tabID])
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
            insertionIndex =
                spaces[spaceIndex].tabs.firstIndex {
                    $0.placement != .pinned
                } ?? spaces[spaceIndex].tabs.endIndex
        } else {
            insertionIndex =
                spaces[spaceIndex].tabs.firstIndex {
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
            let sourceIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        let originalTabs = spaces[spaceIndex].tabs
        var destinationTabs = originalTabs
        let source = destinationTabs.remove(at: sourceIndex)
        guard
            let plan = BrowserTabPlacementPlan(
                moving: source,
                to: placement,
                folderID: requestedFolderID,
                before: destinationTabID,
                in: spaces[spaceIndex],
                among: destinationTabs
            )
        else {
            return false
        }

        let movedTab = plan.placing(source)
        destinationTabs.insert(movedTab, at: plan.insertionIndex)
        guard destinationTabs != originalTabs else { return false }
        guard
            let movedIndex = destinationTabs.firstIndex(where: {
                $0.id == tabID
            })
        else { return false }
        destinationTabs[movedIndex].markPositionModified(at: date)
        // A move can land a tab in the middle of a split run, or carry a member
        // out of one. Repair the affected Space before anyone reads it; the
        // plain normalizer only clears membership, never reorders.
        preserveFolderOrder(in: spaceIndex, removing: [tabID])
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
            let destination = space(id: destinationSpaceID)
        else {
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
            })
        else {
            return false
        }

        let sourceTab = spaces[sourceSpaceIndex].tabs[sourceTabIndex]
        let destinationSpace = spaces[destinationSpaceIndex]
        guard
            let plan = BrowserTabPlacementPlan(
                moving: sourceTab,
                to: requestedPlacement,
                folderID: requestedFolderID,
                before: destinationTabID,
                in: destinationSpace,
                among: destinationSpace.tabs
            )
        else {
            return false
        }

        let sourceWasSelected = spaces[sourceSpaceIndex].selectedTabID == tabID
        preserveFolderOrder(in: sourceSpaceIndex, removing: [tabID])
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

// MARK: - Appearance

extension BrowserSession {
    mutating func updateSelectedTab(
        url: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil
    ) {
        guard let indices = selectedTabIndices else { return }
        spaces[indices.space].tabs[indices.tab].url = url
        if spaces[indices.space].tabs[indices.tab].iconMode == .automatic {
            if let faviconData, !faviconData.isEmpty {
                spaces[indices.space].tabs[indices.tab].faviconData = faviconData
                spaces[indices.space].tabs[indices.tab].faviconURL = url
                spaces[indices.space].tabs[indices.tab].iconAccent = iconAccent
            }
        }
        if let title, !title.isEmpty {
            spaces[indices.space].tabs[indices.tab].title = title
        }
    }

    /// The named-tab twin of ``updateSelectedTab(url:title:faviconData:iconAccent:)``.
    ///
    /// A Split View card observes its own page whether or not it is the focused
    /// one, so an unfocused card needs the same url/title/favicon write against a
    /// tab that is not `selectedTabID`. The field rules are deliberately
    /// identical — automatic icons only, non-empty favicon data, non-empty title
    /// — because a tab must not record different metadata depending on which
    /// card happened to have focus when its page settled.
    @discardableResult
    mutating func updateTab(
        url: URL?,
        title: String?,
        faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: {
                $0.id == tabID
            })
        else { return false }
        spaces[spaceIndex].tabs[tabIndex].url = url
        if spaces[spaceIndex].tabs[tabIndex].iconMode == .automatic {
            if let faviconData, !faviconData.isEmpty {
                spaces[spaceIndex].tabs[tabIndex].faviconData = faviconData
                spaces[spaceIndex].tabs[tabIndex].faviconURL = url
                spaces[spaceIndex].tabs[tabIndex].iconAccent = iconAccent
            }
        }
        if let title, !title.isEmpty {
            spaces[spaceIndex].tabs[tabIndex].title = title
        }
        return true
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
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        let resolvedTitle = BrowserTab.resolvedCustomTitle(title)
        guard spaces[spaceIndex].tabs[tabIndex].customTitle != resolvedTitle else {
            return false
        }
        spaces[spaceIndex].tabs[tabIndex].customTitle = resolvedTitle
        spaces[spaceIndex].tabs[tabIndex].markTitleModified(at: date)
        return true
    }

    @discardableResult
    mutating func setTabEmojiIcon(
        _ emoji: String,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            let normalizedEmoji = BrowserIconSymbol.normalizedEmoji(emoji)
        else { return false }
        spaces[spaceIndex].tabs[tabIndex].symbol = BrowserTab.symbol(
            forEmoji: normalizedEmoji
        )
        spaces[spaceIndex].tabs[tabIndex].faviconData = nil
        spaces[spaceIndex].tabs[tabIndex].faviconURL = nil
        spaces[spaceIndex].tabs[tabIndex].iconAccent = nil
        spaces[spaceIndex].tabs[tabIndex].iconMode = .emoji
        return true
    }

    @discardableResult
    mutating func setTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            !faviconData.isEmpty
        else { return false }
        spaces[spaceIndex].tabs[tabIndex].symbol = "globe"
        spaces[spaceIndex].tabs[tabIndex].faviconData = faviconData
        spaces[spaceIndex].tabs[tabIndex].faviconURL = spaces[spaceIndex].tabs[tabIndex].url
        spaces[spaceIndex].tabs[tabIndex].iconAccent = iconAccent
        spaces[spaceIndex].tabs[tabIndex].iconMode = .pulled
        return true
    }

    @discardableResult
    mutating func cacheAutomaticTabFavicon(
        _ faviconData: Data,
        iconAccent: BrowserTabIconAccent?,
        url: URL,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            spaces[spaceIndex].tabs[tabIndex].iconMode == .automatic,
            !faviconData.isEmpty
        else { return false }
        let currentURL = spaces[spaceIndex].tabs[tabIndex].url
        let normalizedCurrent = currentURL.flatMap(BrowserHistoryURL.normalized) ?? currentURL
        let normalizedCaptured = BrowserHistoryURL.normalized(url) ?? url
        guard normalizedCurrent == normalizedCaptured else { return false }
        spaces[spaceIndex].tabs[tabIndex].symbol = "globe"
        spaces[spaceIndex].tabs[tabIndex].faviconData = faviconData
        spaces[spaceIndex].tabs[tabIndex].faviconURL = url
        spaces[spaceIndex].tabs[tabIndex].iconAccent = iconAccent
        return true
    }

    @discardableResult
    mutating func clearTabIcon(tabID: TabID, in spaceID: SpaceID) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        spaces[spaceIndex].tabs[tabIndex].symbol = "globe"
        spaces[spaceIndex].tabs[tabIndex].faviconData = nil
        spaces[spaceIndex].tabs[tabIndex].faviconURL = nil
        spaces[spaceIndex].tabs[tabIndex].iconAccent = nil
        spaces[spaceIndex].tabs[tabIndex].iconMode = .automatic
        return true
    }

    @discardableResult
    mutating func replaceTabSavedLocationWithCurrent(
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            spaces[spaceIndex].tabs[tabIndex].supportsSavedLocationEditing,
            spaces[spaceIndex].tabs[tabIndex].isAwayFromSavedLocation,
            let currentURL = spaces[spaceIndex].tabs[tabIndex].url
        else {
            return false
        }
        spaces[spaceIndex].tabs[tabIndex].savedURL = currentURL
        return true
    }

    @discardableResult
    mutating func restoreTabSavedLocation(
        tabID: TabID,
        in spaceID: SpaceID
    ) -> URL? {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            spaces[spaceIndex].tabs[tabIndex].isAwayFromSavedLocation,
            let savedURL = spaces[spaceIndex].tabs[tabIndex].savedSiteURL
        else {
            return nil
        }
        spaces[spaceIndex].tabs[tabIndex].url = savedURL
        return savedURL
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
        let retainedGroupIDs = Set(tabs.compactMap(\.splitGroupID))
        spaces[spaceIndex].splitGroups.removeAll {
            !retainedGroupIDs.contains($0.id)
        }
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

// MARK: - Residency

extension BrowserSession {
    @discardableResult
    mutating func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            spaces[spaceIndex].tabs[tabIndex].keepsPageLoaded != keepsPageLoaded
        else { return false }
        spaces[spaceIndex].tabs[tabIndex].keepsPageLoaded = keepsPageLoaded
        return true
    }
}
