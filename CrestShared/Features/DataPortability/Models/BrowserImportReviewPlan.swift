import Foundation

struct BrowserImportReviewPlan: Codable, Equatable, Sendable {
    enum ValidationError: LocalizedError, Equatable, Sendable {
        case noIncludedSpaces

        var errorDescription: String? {
            switch self {
            case .noIncludedSpaces:
                String(localized: "Choose at least one Space to import.")
            }
        }
    }

    private(set) var spaces: [BrowserImportSpaceReview]
    private var destinationCustomizations: [SpaceID: BrowserImportSpaceCustomization]

    init(imported: BrowserPortableImport, existing: BrowserSession) {
        let destinationSpaces =
            existing.hasDisposableSeedState
            ? []
            : existing.spaces
        destinationCustomizations = Dictionary(
            uniqueKeysWithValues: destinationSpaces.map {
                ($0.id, BrowserImportSpaceCustomization(space: $0))
            }
        )
        spaces = imported.spaces.map { sourceSpace in
            let matchingSpace = Self.bestMatchingSpace(
                for: sourceSpace.name,
                in: destinationSpaces
            )
            let destination =
                matchingSpace.map {
                    BrowserImportDestination.existing($0.id)
                } ?? .newSpace
            let duplicateURLs = matchingSpace.map(Self.normalizedURLs(in:)) ?? []
            let duplicateTabIDs: Set<TabID> = Set(
                sourceSpace.tabs.compactMap { tab in
                    guard let url = tab.url,
                        duplicateURLs.contains(Self.normalizedURL(url))
                    else { return nil }
                    return tab.id
                })
            let includedTabIDs = Set(
                sourceSpace.tabs.compactMap { tab in
                    guard let url = tab.url else { return tab.id }
                    return duplicateURLs.contains(Self.normalizedURL(url)) ? nil : tab.id
                })
            return BrowserImportSpaceReview(
                sourceSpace: sourceSpace,
                destination: destination,
                customization: BrowserImportSpaceCustomization(
                    space: matchingSpace ?? sourceSpace
                ),
                includedTabIDs: includedTabIDs,
                duplicateTabIDs: duplicateTabIDs,
                placementOverrides: [:],
                spaceInclusionOverride: nil,
                passwordInclusionOverride: nil
            )
        }
    }

    var hasIncludedSpaces: Bool {
        spaces.contains(where: \.isIncluded)
    }

    mutating func setDestination(
        _ destination: BrowserImportDestination,
        for sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].destination = destination
        switch destination {
        case .newSpace:
            spaces[index].customization = BrowserImportSpaceCustomization(
                space: spaces[index].sourceSpace
            )
        case .existing(let destinationID):
            if let customization = destinationCustomizations[destinationID] {
                spaces[index].customization = customization
            }
        }
    }

    mutating func setTab(
        _ tabID: TabID,
        isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }),
            spaces[index].sourceSpace.contains(tabID)
        else { return }
        if isIncluded {
            spaces[index].spaceInclusionOverride = true
            spaces[index].includedTabIDs.insert(tabID)
        } else {
            spaces[index].includedTabIDs.remove(tabID)
        }
    }

    mutating func setTabs(
        _ tabIDs: Set<TabID>,
        isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        let validTabIDs = Set(spaces[index].sourceSpace.tabs.map(\.id))
        let changedTabIDs = tabIDs.intersection(validTabIDs)
        if isIncluded {
            spaces[index].spaceInclusionOverride = true
            spaces[index].includedTabIDs.formUnion(changedTabIDs)
        } else {
            spaces[index].includedTabIDs.subtract(changedTabIDs)
        }
    }

    mutating func setSpace(
        _ sourceSpaceID: SpaceID,
        isIncluded: Bool
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].spaceInclusionOverride = isIncluded
        if isIncluded {
            let allTabIDs = Set(spaces[index].sourceSpace.tabs.map(\.id))
            spaces[index].includedTabIDs = allTabIDs.subtracting(
                spaces[index].duplicateTabIDs
            )
        } else {
            spaces[index].includedTabIDs.removeAll()
        }
    }

    mutating func setPasswords(
        _ isIncluded: Bool,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].passwordInclusionOverride = isIncluded
    }

    mutating func setPlacement(
        _ placement: TabPlacement,
        for tabID: TabID,
        in sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }),
            spaces[index].sourceSpace.contains(tabID)
        else { return }
        spaces[index].spaceInclusionOverride = true
        spaces[index].placementOverrides[tabID] = placement
        spaces[index].includedTabIDs.insert(tabID)
    }

    mutating func setSpaceIdentity(
        name: String,
        symbol: String,
        for sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].customization.name = name
        spaces[index].customization.symbol = symbol
    }

    mutating func setSpaceBranding(
        _ branding: BrowserSpaceBranding,
        for sourceSpaceID: SpaceID
    ) {
        guard let index = spaces.firstIndex(where: { $0.id == sourceSpaceID }) else {
            return
        }
        spaces[index].customization.branding = branding.normalized()
    }

    func overflowTabIDs(in existing: BrowserSession) -> Set<TabID> {
        var pinnedCounts: [BrowserImportDestinationKey: Int] = [:]
        for space in existing.spaces {
            pinnedCounts[.existing(space.id)] = space.pinnedTabs.count
        }
        var overflow: Set<TabID> = []
        for review in spaces where review.isIncluded {
            let key: BrowserImportDestinationKey =
                switch review.destination {
                case .newSpace: .new(review.id)
                case .existing(let id): .existing(id)
                }
            for tab in review.sourceSpace.tabs
            where review.includedTabIDs.contains(tab.id)
                && review.placement(for: tab) == .pinned
            {
                let count = pinnedCounts[key, default: 0]
                if count >= BrowserSpace.maximumPinnedTabs {
                    overflow.insert(tab.id)
                } else {
                    pinnedCounts[key] = count + 1
                }
            }
        }
        return overflow
    }

    func duplicateTabIDs(in existing: BrowserSession) -> Set<TabID> {
        var duplicates: Set<TabID> = []
        for review in spaces {
            guard case .existing(let destinationID) = review.destination,
                let destination = existing.space(id: destinationID)
            else {
                continue
            }
            let destinationURLs = Self.normalizedURLs(in: destination)
            for tab in review.sourceSpace.tabs {
                guard let url = tab.url,
                    destinationURLs.contains(Self.normalizedURL(url))
                else {
                    continue
                }
                duplicates.insert(tab.id)
            }
        }
        return duplicates
    }

    func matchedDestinationTabIDs(
        for sourceSpaceID: SpaceID,
        in existing: BrowserSession
    ) -> Set<TabID> {
        guard let review = spaces.first(where: { $0.id == sourceSpaceID }),
            review.isIncluded,
            case .existing(let destinationID) = review.destination,
            let destination = existing.space(id: destinationID)
        else {
            return []
        }
        let destinationURLs = Self.normalizedURLs(in: destination)
        let sourceURLs = Set(
            review.sourceSpace.tabs.compactMap { tab -> String? in
                guard let url = tab.url else { return nil }
                let normalizedURL = Self.normalizedURL(url)
                return destinationURLs.contains(normalizedURL) ? normalizedURL : nil
            })
        return Set(
            destination.tabs.compactMap { tab in
                guard let url = tab.url,
                    sourceURLs.contains(Self.normalizedURL(url))
                else { return nil }
                return tab.id
            })
    }

    func preview(mergingInto existing: BrowserSession) throws -> BrowserSession {
        guard hasIncludedSpaces else {
            throw ValidationError.noIncludedSpaces
        }
        let replacesDisposableSeed = existing.hasDisposableSeedState
        let newSpaceCount = spaces.filter { review in
            if case .newSpace = review.destination {
                return review.isIncluded
            }
            return false
        }.count
        guard
            (replacesDisposableSeed ? 0 : existing.spaces.count) + newSpaceCount
                <= BrowserPortableArchive.maximumSpaceCount
        else {
            throw BrowserPortableArchiveError.spaceLimitExceeded(
                BrowserPortableArchive.maximumSpaceCount
            )
        }

        let overflow = overflowTabIDs(in: existing)
        var result = existing
        if replacesDisposableSeed {
            result.spaces.removeAll()
            result.defaultSpaceID = nil
        }
        var firstAffectedSpaceID: SpaceID?
        for review in spaces where review.isIncluded {
            switch review.destination {
            case .newSpace:
                let source = review.sourceSpace
                var created = source
                review.customization.apply(to: &created)
                created.folders = []
                let folderIDMapping = integrateRequiredFolders(
                    from: requiredSourceFolders(for: review),
                    into: &created.folders
                )
                created.tabs = reviewedTabs(
                    from: review,
                    overflow: overflow,
                    folders: &created.folders,
                    folderIDMapping: folderIDMapping
                )
                created.selectedTabID = selectedTabID(
                    source.selectedTabID,
                    in: created.tabs
                )
                result.spaces.append(created)
                firstAffectedSpaceID = firstAffectedSpaceID ?? created.id

            case .existing(let destinationID):
                guard
                    let destinationIndex = result.spaces.firstIndex(where: {
                        $0.id == destinationID
                    })
                else { continue }
                var destination = result.spaces[destinationIndex]
                review.customization.apply(to: &destination)
                let folderIDMapping = integrateRequiredFolders(
                    from: requiredSourceFolders(for: review),
                    into: &destination.folders
                )
                let addedTabs = reviewedTabs(
                    from: review,
                    overflow: overflow,
                    folders: &destination.folders,
                    folderIDMapping: folderIDMapping
                )
                destination.tabs.append(contentsOf: addedTabs)
                if let sourceSelection = review.sourceSpace.selectedTabID,
                    addedTabs.contains(where: { $0.id == sourceSelection })
                {
                    destination.selectedTabID = sourceSelection
                }
                result.spaces[destinationIndex] = destination
                firstAffectedSpaceID = firstAffectedSpaceID ?? destinationID
            }
        }
        if let firstAffectedSpaceID {
            result.selectedSpaceID = firstAffectedSpaceID
            // An import that landed content is the person's own session now, exactly
            // as finishing manual setup is. The seed marker gates every sync stage
            // and leaves the session eligible for wholesale cloud replacement, so an
            // imported Space that kept it would never sync and could be overwritten.
            // Nothing landed means nothing graduated: an import everyone opted out of
            // leaves a fresh install a fresh install.
            result.disposableSeedMarker = nil
        }
        result.repairRuntimeIntegrity()
        return result
    }

    private func reviewedTabs(
        from review: BrowserImportSpaceReview,
        overflow: Set<TabID>,
        folders: inout [BrowserFolder],
        folderIDMapping: [FolderID: FolderID]
    ) -> [BrowserTab] {
        var overflowFolderID = folders.first {
            $0.title.localizedCaseInsensitiveCompare("Imported Pinned Tabs") == .orderedSame
        }?.id
        return review.sourceSpace.tabs.compactMap { sourceTab in
            guard review.includedTabIDs.contains(sourceTab.id) else { return nil }
            var tab = sourceTab
            tab.placement = review.placement(for: sourceTab)
            if overflow.contains(sourceTab.id), tab.placement == .pinned {
                tab.placement = .saved
                if overflowFolderID == nil,
                    folders.count < BrowserSpace.maximumFolderCount
                {
                    let folder = BrowserFolder(
                        title: "Imported Pinned Tabs",
                        symbol: "pin.slash"
                    )
                    folders.append(folder)
                    overflowFolderID = folder.id
                }
                tab.folderID = overflowFolderID
            } else if tab.placement != .saved {
                tab.folderID = nil
            } else {
                tab.folderID = sourceTab.folderID.flatMap { folderIDMapping[$0] }
            }
            tab.savedURL = tab.placement == .current ? nil : tab.savedURL ?? tab.url
            tab.symbol = tab.placement == .pinned ? "pin.fill" : tab.symbol
            return tab
        }
    }

    private func requiredSourceFolders(
        for review: BrowserImportSpaceReview
    ) -> [BrowserFolder] {
        let foldersByID = Dictionary(
            uniqueKeysWithValues: review.sourceSpace.folders.map { ($0.id, $0) }
        )
        var requiredIDs = Set(
            review.sourceSpace.tabs.compactMap { tab -> FolderID? in
                guard review.includedTabIDs.contains(tab.id),
                    review.placement(for: tab) == .saved
                else { return nil }
                return tab.folderID
            })
        var pendingIDs = Array(requiredIDs)
        while let folderID = pendingIDs.popLast(),
            let parentID = foldersByID[folderID]?.parentID,
            requiredIDs.insert(parentID).inserted
        {
            pendingIDs.append(parentID)
        }
        return BrowserFolderTree.repairedPreorder(review.sourceSpace.folders)
            .filter { requiredIDs.contains($0.id) }
    }

    private func integrateRequiredFolders(
        from sourceFolders: [BrowserFolder],
        into destinationFolders: inout [BrowserFolder]
    ) -> [FolderID: FolderID] {
        var folderIDMapping: [FolderID: FolderID] = [:]
        for sourceFolder in sourceFolders {
            let destinationParentID = sourceFolder.parentID.flatMap {
                folderIDMapping[$0]
            }
            if let match = destinationFolders.first(where: {
                $0.parentID == destinationParentID
                    && $0.location == sourceFolder.location
                    && Self.normalizedSpaceName($0.title)
                        == Self.normalizedSpaceName(sourceFolder.title)
            }) {
                folderIDMapping[sourceFolder.id] = match.id
                continue
            }
            guard destinationFolders.count < BrowserSpace.maximumFolderCount else {
                continue
            }
            var destinationID = sourceFolder.id
            if destinationFolders.contains(where: { $0.id == destinationID }) {
                repeat {
                    destinationID = FolderID()
                } while destinationFolders.contains(where: { $0.id == destinationID })
            }
            let folder = BrowserFolder(
                id: destinationID,
                title: sourceFolder.title,
                location: sourceFolder.location,
                symbol: sourceFolder.symbol,
                color: sourceFolder.color,
                parentID: destinationParentID
            )
            destinationFolders.append(folder)
            folderIDMapping[sourceFolder.id] = folder.id
        }
        return folderIDMapping
    }

    private func selectedTabID(
        _ requestedID: TabID?,
        in tabs: [BrowserTab]
    ) -> TabID? {
        if let requestedID, tabs.contains(where: { $0.id == requestedID }) {
            return requestedID
        }
        return tabs.first?.id
    }

    private static func bestMatchingSpace(
        for sourceName: String,
        in existing: [BrowserSpace]
    ) -> BrowserSpace? {
        let sourceKey = normalizedSpaceName(sourceName)
        guard !sourceKey.isEmpty else { return nil }
        return existing.first {
            normalizedSpaceName($0.name) == sourceKey
        }
    }

    private static func normalizedSpaceName(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        return folded.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func normalizedURLs(in space: BrowserSpace) -> Set<String> {
        Set(space.tabs.compactMap { $0.url }.map(normalizedURL))
    }

    private static func normalizedURL(_ url: URL) -> String {
        (BrowserHistoryURL.normalized(url) ?? url).absoluteString
    }
}
