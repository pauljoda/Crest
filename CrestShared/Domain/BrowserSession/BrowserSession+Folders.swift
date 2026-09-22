import Foundation

extension BrowserSession {
    mutating func preserveFolderOrder(in spaceIndex: Int, removing tabIDs: Set<TabID>) {
        guard !tabIDs.isEmpty else { return }
        let space = spaces[spaceIndex]
        spaces[spaceIndex].folders = space.folderTree.preservingOrder(removing: tabIDs, tabs: space.tabs)
    }

    /// Moves the existing subtree. Folder and tab identities never change when
    /// placement changes; callers publish this transaction once.
    @discardableResult
    mutating func moveFolder(
        _ folderID: FolderID, in spaceID: SpaceID, into parentID: FolderID?,
        before siblingID: FolderID? = nil, location: BrowserFolderLocation? = nil,
        beforeTabID: TabID? = nil, at date: Date = .now
    ) -> Bool {
        applyCoreEdit("folder.move", in: spaceID, arguments: [
            "folderId": folderID.rawValue.uuidString,
            "parentId": parentID?.rawValue.uuidString as Any? ?? NSNull(),
            "beforeFolderId": siblingID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": beforeTabID?.rawValue.uuidString as Any? ?? NSNull(),
            "placement": location?.rawValue as Any? ?? NSNull()
        ], at: date)?.changed ?? false
    }

    /// A common folder-membership transaction for menus and drops.
    /// Split members travel together unless an individual-tab drop detaches them.
    @discardableResult
    mutating func fileTabs(
        _ tabIDs: [TabID], in spaceID: SpaceID, into folderID: FolderID?,
        location: BrowserFolderLocation, before requestedAnchorID: TabID? = nil,
        beforeFolderID: FolderID? = nil, detachesSplitMembers: Bool = false, at date: Date = .now
    ) -> Bool {
        applyCoreEdit("tabs.file", in: spaceID, arguments: [
            "tabIds": tabIDs.map { $0.rawValue.uuidString }, "placement": location.rawValue,
            "folderId": folderID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": requestedAnchorID?.rawValue.uuidString as Any? ?? NSNull(),
            "beforeFolderId": beforeFolderID?.rawValue.uuidString as Any? ?? NSNull(),
            "detach": detachesSplitMembers
        ], at: date)?.changed ?? false
    }

    /// Creating a folder around tabs is one transaction: the core places the
    /// folder and files its members together, so a rejected filing cannot
    /// leave an empty folder behind. Title and palette defaults are the
    /// core's and the platform's respective assets.
    @discardableResult
    mutating func createTabFolder(
        _ tabIDs: [TabID], in spaceID: SpaceID, location: BrowserFolderLocation = .current,
        title: String? = nil, color: BrowserSpaceBrandColor = .folderDefault,
        detachesSplitMembers: Bool = false
    ) -> FolderID? {
        let folderID = FolderID()
        guard !tabIDs.isEmpty, spaces.contains(where: { $0.id == spaceID }),
            applyCoreEdit("folder.create", in: spaceID, arguments: [
                "folderId": folderID.rawValue.uuidString,
                "placement": location.rawValue,
                "parentId": NSNull(),
                "title": title as Any? ?? NSNull(),
                "symbol": "folder",
                "color": BrowserCoreSessionEditing.value(color) ?? NSNull(),
                "tabIds": tabIDs.map { $0.rawValue.uuidString },
                "detach": detachesSplitMembers
            ], at: .now) != nil,
            spaces.first(where: { $0.id == spaceID })?.folders.contains(where: { $0.id == folderID }) == true
        else { return nil }
        return folderID
    }
}
