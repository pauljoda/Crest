import Foundation

// Store commands use the owned core session: they send intent and name this
// window, which the core's device moves when the command commits.
extension BrowserStore {
    func createSessionTabFolder(
        _ tabIDs: [TabID], in spaceID: SpaceID,
        detachesSplitMembers: Bool
    ) -> FolderID? {
        guard !tabIDs.isEmpty else { return nil }
        let id = FolderID()
        let arguments = BrowserSessionArguments.FolderCreate(
            folderId: id.rawValue, title: nil, placement: .current, parentId: nil, color: .folderDefault,
            symbol: "folder", tabIds: tabIDs.map(\.rawValue), detach: detachesSplitMembers)
        guard family.execute(.folderCreate, in: spaceID, arguments: arguments, from: self, at: .now) != nil else {
            return nil
        }
        return session.space(id: spaceID)?.folders.contains(where: { $0.id == id }) == true ? id : nil
    }

    /// Records what a page reports about its tab, and answers whether the tab
    /// changed.
    func observeSessionTab(
        url: URL?, title: String?, faviconData: Data?,
        iconAccent: BrowserTabIconAccent?, tabID: TabID, in spaceID: SpaceID
    ) -> Bool {
        guard let tab = session.space(id: spaceID)?.tabs.first(where: { $0.id == tabID }),
            (url ?? tab.url) != tab.url || title != tab.title
                || faviconData != tab.faviconData || iconAccent != tab.iconAccent
        else { return false }
        let arguments = BrowserSessionArguments.TabObserve(
            tabId: tabID.rawValue, url: url?.absoluteString, title: title,
            hasFavicon: !(faviconData?.isEmpty ?? true), faviconChanged: faviconData != tab.faviconData,
            iconAccent: iconAccent)
        let result = family.execute(
            .tabObserve, in: spaceID, arguments: arguments, from: self, at: .now, image: faviconData)
        return result?.changed == true
    }

    func setSessionTabIcon(
        _ mode: TabIconMode, emoji: String? = nil, faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil, tabID: TabID, in spaceID: SpaceID
    ) -> Bool {
        let arguments = BrowserSessionArguments.TabIcon(
            tabId: tabID.rawValue, mode: mode, hasFavicon: !(faviconData?.isEmpty ?? true), iconAccent: iconAccent,
            emoji: emoji)
        return family.execute(.tabIcon, in: spaceID, arguments: arguments, from: self, at: .now, image: faviconData)?
            .changed == true
    }

    func cacheSessionTabFavicon(
        _ faviconData: Data, iconAccent: BrowserTabIconAccent?,
        url: URL, tabID: TabID, in spaceID: SpaceID
    ) -> Bool {
        let arguments = BrowserSessionArguments.TabFaviconCache(
            tabId: tabID.rawValue, url: url.absoluteString, hasFavicon: !faviconData.isEmpty, iconAccent: iconAccent)
        return family.execute(
            .tabFaviconCache, in: spaceID, arguments: arguments, from: self, at: .now, image: faviconData
        )?.changed == true
    }

    func setSessionSavedLocation(_ action: BrowserSavedLocationAction, tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.execute(
            .tabSavedLocation, in: spaceID,
            arguments: BrowserSessionArguments.TabSavedLocation(tabId: tabID.rawValue, action: action),
            from: self, at: .now)?.changed ?? false
    }

    /// Native authentication supplies current access results. The core checks
    /// the owning profiles and completes promotion before an adapter moves a view.
    func promoteTransientPage(
        requestID: UUID, url: URL?, source: BrowserSpaceRuntimeAssignment,
        lease: BrowserSpaceRuntimeAssignment?, destination: BrowserSpaceRuntimeAssignment,
        sourceAccessible: Bool, destinationAccessible: Bool, supportsLiveAdoption: Bool
    ) -> (tabID: TabID?, adoptLivePage: Bool)? {
        guard space(matching: source) != nil, space(matching: destination) != nil else { return nil }
        let date = Date.now
        let tab = url.map {
            BrowserTab(title: $0.host() ?? $0.absoluteString, url: $0, placement: .current, lastActivatedAt: date)
        }
        let arguments = BrowserSessionArguments.TransientPromote(
            requestId: requestID, sourceSpaceId: source.spaceID.rawValue, sourceProfileId: source.profileID,
            leaseSpaceId: lease?.spaceID.rawValue, leaseProfileId: lease?.profileID,
            sourceAccessible: sourceAccessible, destinationAccessible: destinationAccessible,
            supportsLiveAdoption: supportsLiveAdoption, tab: tab)
        guard
            let result = family.execute(
                .transientPromote, in: destination.spaceID, arguments: arguments, from: self, at: date)
        else { return nil }
        stageSync()
        return (result.tabId.map(TabID.init(rawValue:)), result.adoptLivePage == true)
    }

    @discardableResult
    func openSessionTab(
        title: String, url: URL?, nativeContent: BrowserNativeTabContent? = nil,
        symbol: String = "globe", in spaceID: SpaceID, placement: TabPlacement = .current, requestedIndex: Int? = nil,
        insertingAfter origin: TabID? = nil, shouldSelect: Bool = true, at date: Date = .now
    ) -> TabID? {
        let tab = BrowserTab(
            title: title, url: url, nativeContent: nativeContent, symbol: symbol,
            placement: placement, lastActivatedAt: date)
        // The core places a tab opened from `origin` after it and outside its split.
        let arguments = BrowserSessionArguments.TabOpen(
            tab: tab, index: requestedIndex, select: shouldSelect, after: origin?.rawValue)
        guard let id = family.execute(.tabOpen, in: spaceID, arguments: arguments, from: self, at: date)?.tabId
        else { return nil }
        return TabID(rawValue: id)
    }

    /// Closes a tab. A window that showed it returns to the tab it showed
    /// before, which the core's device chooses.
    @discardableResult
    func closeSessionTab(_ id: TabID, in spaceID: SpaceID, resetArchivePlacement: Bool = true) -> Bool {
        let arguments = BrowserSessionArguments.TabClose(
            tabId: id.rawValue, resetArchivePlacement: resetArchivePlacement)
        return family.execute(.tabClose, in: spaceID, arguments: arguments, from: self, at: .now) != nil
    }

    @discardableResult
    func deleteSessionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        family.execute(
            .tabDelete, in: spaceID, arguments: BrowserSessionArguments.Tab(tabId: id.rawValue),
            from: self, at: .now) != nil
    }

    func clearSessionTabs(in spaceID: SpaceID) -> Bool {
        family.execute(.tabClearCurrent, in: spaceID, arguments: BrowserCoreNoArguments(), from: self, at: .now) != nil
    }

    func renameSessionTab(_ title: String?, tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.execute(
            .tabRename, in: spaceID, arguments: BrowserSessionArguments.TabRename(tabId: tabID.rawValue, title: title),
            from: self, at: .now)?.changed ?? false
    }

    func setSessionTabResidency(_ keep: Bool, tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.execute(
            .tabResidency, in: spaceID,
            arguments: BrowserSessionArguments.TabResidency(tabId: tabID.rawValue, keep: keep),
            from: self, at: .now)?.changed ?? false
    }

    func renameSessionFolder(_ id: FolderID, in spaceID: SpaceID, title: String) -> Bool {
        family.execute(
            .folderRename, in: spaceID,
            arguments: BrowserSessionArguments.FolderRename(folderId: id.rawValue, title: title),
            from: self, at: .now)?.changed ?? false
    }

    func collapseSessionFolder(_ id: FolderID, in spaceID: SpaceID, isCollapsed: Bool) -> Bool {
        family.execute(
            .folderCollapse, in: spaceID,
            arguments: BrowserSessionArguments.FolderCollapse(folderId: id.rawValue, collapsed: isCollapsed),
            from: self, at: .now)?.changed ?? false
    }

    func deleteSessionFolder(_ id: FolderID, in spaceID: SpaceID) -> Bool {
        family.execute(
            .folderDelete, in: spaceID, arguments: BrowserSessionArguments.Folder(folderId: id.rawValue),
            from: self, at: .now)?.changed ?? false
    }

    func moveSessionFolder(
        _ id: FolderID, in spaceID: SpaceID, into parentID: FolderID?,
        before siblingID: FolderID? = nil, location: BrowserFolderLocation? = nil, beforeTabID: TabID? = nil
    ) -> Bool {
        let arguments = BrowserSessionArguments.FolderMove(
            folderId: id.rawValue, parentId: parentID?.rawValue, beforeFolderId: siblingID?.rawValue,
            before: beforeTabID?.rawValue, placement: location)
        return family.execute(.folderMove, in: spaceID, arguments: arguments, from: self, at: .now)?.changed ?? false
    }

    func fileSessionTabs(
        _ ids: [TabID], in spaceID: SpaceID, into folderID: FolderID?,
        location: BrowserFolderLocation, before anchor: TabID? = nil, beforeFolderID: FolderID? = nil,
        detachesSplitMembers: Bool = false
    ) -> Bool {
        let arguments = BrowserSessionArguments.TabsFile(
            tabIds: ids.map(\.rawValue), placement: location, folderId: folderID?.rawValue, before: anchor?.rawValue,
            beforeFolderId: beforeFolderID?.rawValue, detach: detachesSplitMembers)
        return family.execute(.tabsFile, in: spaceID, arguments: arguments, from: self, at: .now)?.changed ?? false
    }
}
