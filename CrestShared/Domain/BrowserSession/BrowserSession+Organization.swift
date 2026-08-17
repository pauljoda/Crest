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
        in spaceID: SpaceID
    ) -> FolderID? {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            spaces[spaceIndex].folders.count < BrowserSpace.maximumFolderCount
        else {
            return nil
        }
        let tree = spaces[spaceIndex].folderTree
        if let parentID {
            guard let parentDepth = tree.depth(of: parentID),
                parentDepth + 1 < BrowserSpace.maximumFolderDepth
            else { return nil }
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = SavedFolder(
            title: trimmedTitle.isEmpty ? "Untitled Folder" : trimmedTitle,
            symbol: trimmedSymbol.isEmpty ? "folder" : trimmedSymbol,
            color: color,
            parentID: parentID
        )
        let insertionIndex: Int
        if let parentID {
            let subtreeIDs = tree.descendants(of: parentID).union([parentID])
            insertionIndex =
                spaces[spaceIndex].folders.lastIndex {
                    subtreeIDs.contains($0.id)
                }.map { spaces[spaceIndex].folders.index(after: $0) }
                ?? spaces[spaceIndex].folders.endIndex
        } else {
            insertionIndex = spaces[spaceIndex].folders.endIndex
        }
        spaces[spaceIndex].folders.insert(folder, at: insertionIndex)
        return folder.id
    }

    @discardableResult
    mutating func renameFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        title: String
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let folderIndex = spaces[spaceIndex].folders.firstIndex(where: {
                $0.id == folderID
            })
        else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = trimmedTitle.isEmpty ? "Untitled Folder" : trimmedTitle
        guard spaces[spaceIndex].folders[folderIndex].title != resolvedTitle else { return false }
        spaces[spaceIndex].folders[folderIndex].title = resolvedTitle
        return true
    }

    @discardableResult
    mutating func setFolderColor(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        color: BrowserSpaceBrandColor
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let folderIndex = spaces[spaceIndex].folders.firstIndex(where: {
                $0.id == folderID
            }),
            spaces[spaceIndex].folders[folderIndex].color != color
        else {
            return false
        }
        spaces[spaceIndex].folders[folderIndex].color = color
        return true
    }

    @discardableResult
    mutating func setFolderCollapsed(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        isCollapsed: Bool,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let folderIndex = spaces[spaceIndex].folders.firstIndex(where: {
                $0.id == folderID
            }),
            spaces[spaceIndex].folders[folderIndex].isCollapsed
                != isCollapsed
        else {
            return false
        }
        spaces[spaceIndex].folders[folderIndex].isCollapsed = isCollapsed
        spaces[spaceIndex].folders[folderIndex].collapseModifiedAt = date
        return true
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

    @discardableResult
    mutating func moveFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        into parentID: FolderID?,
        before siblingID: FolderID? = nil
    ) -> Bool {
        guard canMoveFolder(folderID, in: spaceID, into: parentID),
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else {
            return false
        }
        let tree = spaces[spaceIndex].folderTree
        let subtreeIDs = tree.descendants(of: folderID).union([folderID])
        guard siblingID.map({ !subtreeIDs.contains($0) }) ?? true else { return false }

        var moving = spaces[spaceIndex].folders.filter { subtreeIDs.contains($0.id) }
        var remaining = spaces[spaceIndex].folders.filter { !subtreeIDs.contains($0.id) }
        guard let rootIndex = moving.firstIndex(where: { $0.id == folderID }) else { return false }
        moving[rootIndex].parentID = parentID

        let insertionIndex: Int
        if let siblingID,
            let siblingIndex = remaining.firstIndex(where: {
                $0.id == siblingID && $0.parentID == parentID
            })
        {
            insertionIndex = siblingIndex
        } else if let parentID {
            let remainingTree = BrowserFolderTree(folders: remaining)
            let parentSubtreeIDs = remainingTree.descendants(of: parentID).union([parentID])
            insertionIndex =
                remaining.lastIndex {
                    parentSubtreeIDs.contains($0.id)
                }.map { remaining.index(after: $0) } ?? remaining.endIndex
        } else {
            insertionIndex = remaining.endIndex
        }

        remaining.insert(contentsOf: moving, at: insertionIndex)
        let reordered = BrowserFolderTree(folders: remaining).foldersInDisplayOrder
        guard reordered != spaces[spaceIndex].folders else { return false }
        spaces[spaceIndex].folders = reordered
        return true
    }

    /// Removes only the container. Direct tabs remain saved at the deleted folder's
    /// parent, while direct child folders are promoted one level without losing content.
    @discardableResult
    mutating func deleteFolder(
        _ folderID: FolderID,
        in spaceID: SpaceID,
        at date: Date = .now
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let folderIndex = spaces[spaceIndex].folders.firstIndex(where: {
                $0.id == folderID
            })
        else { return false }
        let parentID = spaces[spaceIndex].folders[folderIndex].parentID
        spaces[spaceIndex].folders.remove(at: folderIndex)
        for index in spaces[spaceIndex].folders.indices
        where spaces[spaceIndex].folders[index].parentID == folderID {
            spaces[spaceIndex].folders[index].parentID = parentID
        }
        for index in spaces[spaceIndex].tabs.indices
        where spaces[spaceIndex].tabs[index].folderID == folderID {
            spaces[spaceIndex].tabs[index].folderID = parentID
            spaces[spaceIndex].tabs[index].markPositionModified(at: date)
        }
        spaces[spaceIndex].folders =
            BrowserFolderTree(
                folders: spaces[spaceIndex].folders
            ).foldersInDisplayOrder
        return true
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
        guard let spaceIndex = selectedSpaceIndex else { return }
        guard let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else { return }
        spaces[spaceIndex].tabs[tabIndex].lastActivatedAt = date
        spaces[spaceIndex].selectedTabID = tabID
    }

    mutating func clearTabSelection(in spaceID: SpaceID) {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }) else {
            return
        }
        spaces[spaceIndex].selectedTabID = nil
    }

}
