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
        return try BrowserCoreWorkspaceImport.preview(BrowserCoreWorkspaceImport.review(self), existing: existing)
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
