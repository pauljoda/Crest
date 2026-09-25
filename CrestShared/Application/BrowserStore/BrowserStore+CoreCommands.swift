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
            workspaceID: family.workspaceID, spaceID: spaceID, folderID: id, placement: .current,
            parentID: nil, title: nil, color: BrowserSpaceBrandColor.folderDefault.core, symbol: "folder",
            tabIDs: tabIDs, leavesSplits: detachesSplitMembers)
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
            workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID, mode: mode, emoji: emoji,
            accent: iconAccent.map { TabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) })
        return family.perform(choice, from: self, offering: faviconData) != nil
    }

    /// Makes the page a saved or pinned tab shows the one it belongs to, and
    /// answers whether that changed its saved address.
    func replaceSessionSavedAddress(tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.send(
            ReplaceSavedAddress(workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID),
            from: self)
    }

    /// Returns a saved or pinned tab to the address it belongs to, and answers
    /// whether the core accepted it, including for a tab already there.
    func returnSessionTabToSavedAddress(tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.perform(
            ReturnToSavedAddress(workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID),
            from: self) != nil
    }

    /// Keeps a Quick Window's or Peek's page as a new tab of `spaceID` at the
    /// address the page shows, which this window then shows, and answers the
    /// core's promotion: the tab's identity and whether the tab may take the
    /// live page. Nil when a rule refused it, such as a locked Space or a page
    /// already kept.
    func promoteTransientPage(_ page: CorePage, into spaceID: SpaceID) -> TransientPagePromoted? {
        let promotion = PromoteTransientPage(
            workspaceID: family.workspaceID, windowID: windowID, pageID: page.id, spaceID: spaceID,
            placement: .current)
        return family.perform(promotion, from: self)?.changes.lazy.compactMap {
            guard case .transientPagePromoted(let promoted) = $0, promoted.pageID == page.id else { return nil }
            return promoted
        }.first
    }

    /// Opens a tab showing `content` in `placement`'s section and answers its
    /// identity, or nil when the core refused it. The core places a tab
    /// opened from `origin` after it and outside its split, resolves its
    /// address and names a page it was given no title for.
    @discardableResult
    func openSessionTab(
        _ content: TabContent, in spaceID: SpaceID, placement: TabPlacement = .current,
        insertingAfter origin: TabID? = nil, shouldSelect: Bool = true
    ) -> TabID? {
        let id = TabID()
        let opening = OpenTab(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID, tabID: id,
            content: content, placement: placement, afterTabID: origin, shows: shouldSelect)
        return family.perform(opening, from: self) == nil ? nil : id
    }

    /// Closes a tab the way its section closes one: the core archives an open
    /// tab and puts a saved or pinned tab's page away. A window that showed it
    /// returns to the tab it showed before, which the core's device chooses.
    @discardableResult
    func closeSessionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        family.perform(
            CloseTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                tabID: id),
            from: self) != nil
    }

    /// Whether closing `id` leaves only its window to close: the core keeps
    /// the Start Page that is its Space's only tab.
    func closingLeavesOnlyTheWindow(_ id: TabID, in spaceID: SpaceID) -> Bool {
        let closing = CloseTab(
            workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID, tabID: id)
        guard case .lastStartPage = family.refusal(of: closing, from: self) else { return false }
        return true
    }

    @discardableResult
    func deleteSessionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        family.perform(
            DeleteTab(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                tabID: id),
            from: self) != nil
    }

    func clearSessionTabs(in spaceID: SpaceID) -> Bool {
        family.perform(
            ClearCurrentTabs(workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID),
            from: self) != nil
    }

    func renameSessionTab(_ title: String?, tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.send(
            RenameTab(workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID, title: title),
            from: self)
    }

    func setSessionTabResidency(_ keep: Bool, tabID: TabID, in spaceID: SpaceID) -> Bool {
        family.send(
            KeepPageLoaded(
                workspaceID: family.workspaceID, spaceID: spaceID, tabID: tabID, keeps: keep),
            from: self)
    }

    func renameSessionFolder(_ id: FolderID, in spaceID: SpaceID, title: String) -> Bool {
        family.send(
            RenameFolder(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: id, title: title),
            from: self)
    }

    func collapseSessionFolder(_ id: FolderID, in spaceID: SpaceID, isCollapsed: Bool) -> Bool {
        family.send(
            CollapseFolder(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: id,
                collapsed: isCollapsed),
            from: self)
    }

    func deleteSessionFolder(_ id: FolderID, in spaceID: SpaceID) -> Bool {
        family.send(
            DeleteFolder(workspaceID: family.workspaceID, spaceID: spaceID, folderID: id),
            from: self)
    }

    func moveSessionFolder(
        _ id: FolderID, in spaceID: SpaceID, into parentID: FolderID?,
        before siblingID: FolderID? = nil, location: BrowserFolderLocation? = nil, beforeTabID: TabID? = nil
    ) -> Bool {
        family.send(
            MoveFolder(
                workspaceID: family.workspaceID, spaceID: spaceID, folderID: id,
                placement: location?.tabPlacement, parentID: parentID, beforeFolderID: siblingID,
                beforeTabID: beforeTabID),
            from: self)
    }

    func fileSessionTabs(
        _ ids: [TabID], in spaceID: SpaceID, into folderID: FolderID?,
        location: BrowserFolderLocation, before anchor: TabID? = nil, beforeFolderID: FolderID? = nil,
        detachesSplitMembers: Bool = false
    ) -> Bool {
        family.send(
            FileTabs(
                workspaceID: family.workspaceID, windowID: windowID, spaceID: spaceID,
                selection: TabSelection(tabIDs: ids, folderIDs: [], memberTabIDs: ids),
                placement: location.tabPlacement, folderID: folderID, beforeTabID: anchor,
                beforeFolderID: beforeFolderID, leavesSplits: detachesSplitMembers),
            from: self)
    }
}

extension TabContent {
    /// The Start Page, which the core names.
    static let startPage = TabContent(address: nil, view: nil, title: nil, symbol: nil)

    /// The page at `url`, called `title` until it reports its own, or by its
    /// host when the core is given no title.
    static func page(_ url: URL, title: String? = nil) -> TabContent {
        TabContent(address: url.absoluteString, view: nil, title: title, symbol: nil)
    }

    /// A native view, titled and drawn as this platform names it.
    static func view(_ content: BrowserNativeTabContent, title: String, symbol: String) -> TabContent {
        TabContent(
            address: nil, view: NativeTabContent(kind: content.kind, resourceID: content.resourceID), title: title,
            symbol: symbol)
    }
}
