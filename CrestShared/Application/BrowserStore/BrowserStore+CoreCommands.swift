import Foundation

// Store commands use the owned core session. Value-only session operations remain
// available for imports, prepared transfers, and the legacy composition root.
extension BrowserStore {
    /// Native authentication supplies current access results. The core checks
    /// the owning profiles and completes promotion before an adapter moves a view.
    func promoteTransientPage(requestID: UUID, url: URL?, source: BrowserSpaceRuntimeAssignment,
        lease: BrowserSpaceRuntimeAssignment?, destination: BrowserSpaceRuntimeAssignment,
        sourceAccessible: Bool, destinationAccessible: Bool, supportsLiveAdoption: Bool
    ) -> (tabID: TabID?, adoptLivePage: Bool)? {
        guard space(matching: source) != nil, space(matching: destination) != nil else { return nil }
        let date = Date.now
        let tab = url.flatMap { BrowserCoreSessionEditing.tabValue(BrowserTab(
            title: $0.host() ?? $0.absoluteString, url: $0, placement: .current, lastActivatedAt: date)) }
        guard let result = family.execute("transient.promote", in: destination.spaceID, arguments: [
            "requestId": requestID.uuidString,
            "sourceSpaceId": source.spaceID.rawValue.uuidString, "sourceProfileId": source.profileID.uuidString,
            "leaseSpaceId": lease?.spaceID.rawValue.uuidString as Any? ?? NSNull(),
            "leaseProfileId": lease?.profileID.uuidString as Any? ?? NSNull(),
            "sourceAccessible": sourceAccessible, "destinationAccessible": destinationAccessible,
            "supportsLiveAdoption": supportsLiveAdoption, "tab": tab ?? NSNull()
        ], from: self, at: date) else { return nil }
        persist(scope: .core)
        return (result.tabId.map(TabID.init(rawValue:)), result.adoptLivePage == true)
    }

    @discardableResult
    func openSessionTab(title: String, url: URL?, nativeContent: BrowserNativeTabContent? = nil,
        symbol: String = "globe", in spaceID: SpaceID, placement: TabPlacement = .current, requestedIndex: Int? = nil,
        shouldSelect: Bool = true, at date: Date = .now) -> TabID? {
        let tab = BrowserTab(title: title, url: url, nativeContent: nativeContent, symbol: symbol,
            placement: placement, lastActivatedAt: date)
        guard let value = BrowserCoreSessionEditing.tabValue(tab),
            let id = family.execute("tab.open", in: spaceID, arguments: [
                "tab": value, "index": requestedIndex as Any? ?? NSNull(), "select": shouldSelect
            ], from: self, at: date)?.tabId else { return nil }
        return TabID(rawValue: id)
    }

    @discardableResult
    func activateSessionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        return family.execute("tab.activate", in: spaceID, arguments: ["tabId": id.rawValue.uuidString],
            from: self, at: .now) != nil
    }

    @discardableResult
    func closeSessionTab(_ id: TabID, in spaceID: SpaceID, fallbackTabID: TabID? = nil,
        resetArchivePlacement: Bool = true) -> Bool {
        return family.execute("tab.close", in: spaceID, arguments: [
            "tabId": id.rawValue.uuidString, "fallbackTabId": fallbackTabID?.rawValue.uuidString as Any? ?? NSNull(),
            "resetArchivePlacement": resetArchivePlacement
        ], from: self, at: .now) != nil
    }

    @discardableResult
    func deleteSessionTab(_ id: TabID, in spaceID: SpaceID) -> Bool {
        return family.execute("tab.delete", in: spaceID, arguments: ["tabId": id.rawValue.uuidString],
            from: self, at: .now) != nil
    }

    func clearSessionTabs(in spaceID: SpaceID) -> Bool {
        return family.execute("tab.clear_current", in: spaceID, arguments: [:], from: self, at: .now) != nil
    }

    func renameSessionTab(_ title: String?, tabID: TabID, in spaceID: SpaceID) -> Bool {
        return family.execute("tab.rename", in: spaceID, arguments: [
            "tabId": tabID.rawValue.uuidString, "title": title as Any? ?? NSNull()
        ], from: self, at: .now)?.changed ?? false
    }

    func setSessionTabResidency(_ keep: Bool, tabID: TabID, in spaceID: SpaceID) -> Bool {
        return family.execute("tab.residency", in: spaceID,
            arguments: ["tabId": tabID.rawValue.uuidString, "keep": keep], from: self, at: .now)?.changed ?? false
    }

    func renameSessionFolder(_ id: FolderID, in spaceID: SpaceID, title: String) -> Bool {
        return family.execute("folder.rename", in: spaceID,
            arguments: ["folderId": id.rawValue.uuidString, "title": title], from: self, at: .now)?.changed ?? false
    }

    func collapseSessionFolder(_ id: FolderID, in spaceID: SpaceID, isCollapsed: Bool) -> Bool {
        return family.execute("folder.collapse", in: spaceID,
            arguments: ["folderId": id.rawValue.uuidString, "collapsed": isCollapsed], from: self, at: .now)?.changed ?? false
    }

    func deleteSessionFolder(_ id: FolderID, in spaceID: SpaceID) -> Bool {
        return family.execute("folder.delete", in: spaceID,
            arguments: ["folderId": id.rawValue.uuidString], from: self, at: .now)?.changed ?? false
    }

    func moveSessionFolder(_ id: FolderID, in spaceID: SpaceID, into parentID: FolderID?,
        before siblingID: FolderID? = nil, location: BrowserFolderLocation? = nil, beforeTabID: TabID? = nil) -> Bool {
        return family.execute("folder.move", in: spaceID, arguments: [
            "folderId": id.rawValue.uuidString, "parentId": parentID?.rawValue.uuidString as Any? ?? NSNull(),
            "beforeFolderId": siblingID?.rawValue.uuidString as Any? ?? NSNull(),
            "before": beforeTabID?.rawValue.uuidString as Any? ?? NSNull(), "placement": location?.rawValue as Any? ?? NSNull()
        ], from: self, at: .now)?.changed ?? false
    }

    func fileSessionTabs(_ ids: [TabID], in spaceID: SpaceID, into folderID: FolderID?,
        location: BrowserFolderLocation, before anchor: TabID? = nil, beforeFolderID: FolderID? = nil,
        detachesSplitMembers: Bool = false) -> Bool {
        return family.execute("tabs.file", in: spaceID, arguments: [
            "tabIds": ids.map { $0.rawValue.uuidString }, "placement": location.rawValue,
            "folderId": folderID?.rawValue.uuidString as Any? ?? NSNull(), "before": anchor?.rawValue.uuidString as Any? ?? NSNull(),
            "beforeFolderId": beforeFolderID?.rawValue.uuidString as Any? ?? NSNull(), "detach": detachesSplitMembers
        ], from: self, at: .now)?.changed ?? false
    }
}
