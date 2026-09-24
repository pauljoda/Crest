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
        let creation = CreateFolder(
            workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: id.rawValue, placement: .current,
            parentID: nil, title: nil, color: BrowserSpaceBrandColor.folderDefault.core, symbol: "folder",
            tabIDs: tabIDs.map(\.rawValue), leavesSplits: detachesSplitMembers)
        guard family.send(creation, from: self) else { return nil }
        return session.space(id: spaceID)?.folders.contains(where: { $0.id == id }) == true ? id : nil
    }

    /// Chooses how a tab's icon is filled, and answers whether the core
    /// accepted the choice. A pulled icon wears `faviconData`, the image this
    /// platform holds for the page, so it needs one.
    func setSessionTabIcon(
        _ mode: TabIconMode, emoji: String? = nil, faviconData: Data? = nil,
        iconAccent: BrowserTabIconAccent? = nil, tabID: TabID, in spaceID: SpaceID
    ) -> Bool {
        guard !mode.requiresFavicon || faviconData?.isEmpty == false else { return false }
        let choice = ChooseTabIcon(
            workspaceID: family.workspaceID, spaceID: spaceID.rawValue, tabID: tabID.rawValue, mode: mode, emoji: emoji,
            accent: iconAccent.map { TabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) })
        return family.perform(choice, from: self, offering: faviconData) != nil
    }

    /// Makes the page a saved or pinned tab shows the one it belongs to, and
    /// answers whether that changed its saved address.
    func replaceSessionSavedAddress(tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.send(
            ReplaceSavedAddress(workspaceID: family.workspaceID, spaceID: spaceID.rawValue, tabID: tabID.rawValue),
            from: self)
    }

    /// Returns a saved or pinned tab to the address it belongs to, and answers
    /// whether the core accepted it, including for a tab already there.
    func returnSessionTabToSavedAddress(tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.perform(
            ReturnToSavedAddress(workspaceID: family.workspaceID, spaceID: spaceID.rawValue, tabID: tabID.rawValue),
            from: self) != nil
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
        family.send(
            RenameTab(workspaceID: family.workspaceID, spaceID: spaceID.rawValue, tabID: tabID.rawValue, title: title),
            from: self)
    }

    func setSessionTabResidency(_ keep: Bool, tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.send(
            KeepPageLoaded(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, tabID: tabID.rawValue, keeps: keep),
            from: self)
    }

    func renameSessionFolder(_ id: FolderID, in spaceID: SpaceID, title: String) -> Bool {
        family.send(
            RenameFolder(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: id.rawValue, title: title),
            from: self)
    }

    func collapseSessionFolder(_ id: FolderID, in spaceID: SpaceID, isCollapsed: Bool) -> Bool {
        family.send(
            CollapseFolder(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: id.rawValue,
                collapsed: isCollapsed),
            from: self)
    }

    func deleteSessionFolder(_ id: FolderID, in spaceID: SpaceID) -> Bool {
        family.send(
            DeleteFolder(workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: id.rawValue),
            from: self)
    }

    func moveSessionFolder(
        _ id: FolderID, in spaceID: SpaceID, into parentID: FolderID?,
        before siblingID: FolderID? = nil, location: BrowserFolderLocation? = nil, beforeTabID: TabID? = nil
    ) -> Bool {
        family.send(
            MoveFolder(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, folderID: id.rawValue,
                placement: location?.tabPlacement, parentID: parentID?.rawValue, beforeFolderID: siblingID?.rawValue,
                beforeTabID: beforeTabID?.rawValue),
            from: self)
    }

    func fileSessionTabs(
        _ ids: [TabID], in spaceID: SpaceID, into folderID: FolderID?,
        location: BrowserFolderLocation, before anchor: TabID? = nil, beforeFolderID: FolderID? = nil,
        detachesSplitMembers: Bool = false
    ) -> Bool {
        family.send(
            FileTabs(
                workspaceID: family.workspaceID, spaceID: spaceID.rawValue, tabIDs: ids.map(\.rawValue),
                placement: location.tabPlacement, folderID: folderID?.rawValue, beforeTabID: anchor?.rawValue,
                beforeFolderID: beforeFolderID?.rawValue, leavesSplits: detachesSplitMembers),
            from: self)
    }
}
