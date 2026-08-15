import Foundation

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
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID })
        else {
            return false
        }
        let wasSelected = spaces[spaceIndex].selectedTabID == tabID
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
        spaces[spaceIndex].tabs.remove(at: tabIndex)
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
