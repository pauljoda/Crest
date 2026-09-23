import Foundation

// MARK: - Folders

extension BrowserSession {
    @discardableResult
    mutating func setSavedTabsExpanded(
        _ isExpanded: Bool,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            spaces[spaceIndex].isSavedTabsExpanded != isExpanded
        else {
            return false
        }
        spaces[spaceIndex].isSavedTabsExpanded = isExpanded
        spaces[spaceIndex].savedTabsExpansionModifiedAt = date
        return true
    }

    @discardableResult
    mutating func addFolder(
        title: String = "New Folder",
        symbol: String = "folder",
        color: BrowserSpaceBrandColor = .folderDefault,
        parentID: FolderID? = nil,
        location: BrowserFolderLocation = .saved,
        in spaceID: SpaceID
    ) -> FolderID? {
        let id = FolderID()
        guard applyCoreEdit("folder.create", in: spaceID, arguments: [
            "folderId": id.rawValue.uuidString, "title": title, "placement": location.rawValue,
            "parentId": parentID?.rawValue.uuidString as Any? ?? NSNull()
        ], at: .now) != nil,
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let index = spaces[spaceIndex].folders.firstIndex(where: { $0.id == id })
        else { return nil }
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        spaces[spaceIndex].folders[index].symbol = trimmedSymbol.isEmpty ? "folder" : trimmedSymbol
        spaces[spaceIndex].folders[index].color = color
        return id
    }

    @discardableResult
    mutating func renameFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        title: String
    ) -> Bool {
        applyCoreEdit("folder.rename", in: spaceID, arguments: [
            "folderId": folderID.rawValue.uuidString, "title": title
        ], at: .now)?.changed ?? false
    }

    @discardableResult
    mutating func setFolderCollapsed(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        isCollapsed: Bool,
        at date: Date = .now
    ) -> Bool {
        applyCoreEdit("folder.collapse", in: spaceID, arguments: [
            "folderId": folderID.rawValue.uuidString, "collapsed": isCollapsed
        ], at: date)?.changed ?? false
    }

    func canMoveFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        into parentID: FolderID?
    ) -> Bool {
        guard let space = space(id: spaceID),
            let sourceDepth = space.folderTree.depth(of: folderID)
        else { return false }
        let tree = space.folderTree
        let descendants = tree.descendants(of: folderID)
        if parentID == folderID || parentID.map(descendants.contains) == true {
            return false
        }
        let destinationDepth: Int
        if let parentID {
            guard let parentDepth = tree.depth(of: parentID) else { return false }
            destinationDepth = parentDepth + 1
        } else {
            destinationDepth = 0
        }
        let subtreeMaximumDepth = descendants.compactMap(tree.depth).max() ?? sourceDepth
        let relativeDepth = subtreeMaximumDepth - sourceDepth
        return destinationDepth + relativeDepth < BrowserSpace.maximumFolderDepth
    }

    /// Removes only the container. Direct tabs remain saved at the deleted folder's
    /// parent, while direct child folders are promoted one level without losing content.
    @discardableResult
    mutating func deleteFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        applyCoreEdit("folder.delete", in: spaceID,
            arguments: ["folderId": folderID.rawValue.uuidString], at: date)?.changed ?? false
    }

}

// MARK: - Spaces

extension BrowserSession {
    mutating func addSpace() {
        let number = spaces.count + 1
        let space = Self.makeBlankSpace(number: number)
        spaces.append(space)
        selectedSpaceID = space.id
    }

    @discardableResult
    mutating func removeSpace(_ spaceID: SpaceID) -> BrowserSpace? {
        guard spaces.count > 1,
            let index = spaces.firstIndex(where: { $0.id == spaceID })
        else {
            return nil
        }
        let wasSelected = selectedSpaceID == spaceID
        let removed = spaces.remove(at: index)
        if wasSelected {
            selectedSpaceID = spaces[min(index, spaces.index(before: spaces.endIndex))].id
        }
        if defaultSpaceID == spaceID {
            defaultSpaceID = selectedSpaceID
        }
        ensureSelection(in: selectedSpaceID)
        return removed
    }

    mutating func updateSpaceAccessPolicy(
        _ accessPolicy: BrowserSpaceAccessPolicy,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].accessPolicy = accessPolicy
    }

    mutating func updateSpaceIdentity(
        _ spaceID: SpaceID,
        name: String,
        symbol: String,
        accent: SpaceAccent
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        spaces[spaceIndex].name = trimmedName.isEmpty ? "Untitled Space" : trimmedName
        spaces[spaceIndex].symbol = trimmedSymbol.isEmpty ? "square.grid.2x2" : trimmedSymbol
        spaces[spaceIndex].accent = accent
    }

    mutating func updateSpaceBranding(
        _ branding: BrowserSpaceBranding,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].branding = branding.normalized()
    }

    mutating func moveSpaces(from source: IndexSet, to destination: Int) {
        let validOffsets = source.filter(spaces.indices.contains)
        guard !validOffsets.isEmpty else { return }
        let movedSpaces = validOffsets.map { spaces[$0] }
        for offset in validOffsets.reversed() {
            spaces.remove(at: offset)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            spaces.endIndex
        )
        spaces.insert(contentsOf: movedSpaces, at: insertionIndex)
    }

    mutating func updateCredentialPreferences(
        _ preferences: BrowserCredentialPreferences,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].credentialPreferences = preferences
    }

    mutating func updateBrowsingPreferences(
        _ preferences: BrowserSpaceBrowsingPreferences,
        in spaceID: SpaceID
    ) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        spaces[spaceIndex].browsingPreferences = preferences
    }
}

// MARK: - Selection

extension BrowserSession {
    mutating func selectSpace(_ spaceID: SpaceID) {
        guard spaces.contains(where: { $0.id == spaceID }) else { return }
        selectedSpaceID = spaceID
        ensureSelection(in: spaceID)
    }

    mutating func setDefaultSpace(_ spaceID: SpaceID) {
        guard spaces.contains(where: { $0.id == spaceID }) else { return }
        defaultSpaceID = spaceID
    }

    mutating func selectDefaultSpaceForLaunch() {
        guard let defaultSpaceID,
            spaces.contains(where: { $0.id == defaultSpaceID })
        else { return }
        selectSpace(defaultSpaceID)
    }

    mutating func selectTab(_ tabID: TabID, at date: Date = .now) {
        _ = activateTab(tabID, in: selectedSpaceID, at: date)
    }

    mutating func clearTabSelection(in spaceID: SpaceID) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else {
            return
        }
        spaces[spaceIndex].selectedTabID = nil
    }

}
