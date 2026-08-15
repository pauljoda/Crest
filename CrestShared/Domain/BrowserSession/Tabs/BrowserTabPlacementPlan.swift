struct BrowserTabPlacementPlan: Equatable, Sendable {
    let insertionIndex: Int

    private let destinationSection: BrowserTabPlacementDestinationSection

    init?(
        moving tab: BrowserTab,
        to requestedPlacement: TabPlacement? = nil,
        folderID requestedFolderID: FolderID? = nil,
        before destinationTabID: TabID? = nil,
        in destinationSpace: BrowserSpace,
        among destinationTabs: [BrowserTab]
    ) {
        guard destinationTabID != tab.id else { return nil }
        guard !destinationTabs.contains(where: { $0.id == tab.id }) else {
            return nil
        }

        let placement = requestedPlacement ?? tab.placement
        let folderID = Self.resolvedFolderID(
            requestedFolderID,
            for: placement,
            in: destinationSpace
        )
        let destinationSection = BrowserTabPlacementDestinationSection(
            placement: placement,
            folderID: folderID
        )
        guard destinationSection.hasCapacity(in: destinationTabs) else { return nil }

        self.destinationSection = destinationSection
        insertionIndex = destinationSection.insertionIndex(
            before: destinationTabID,
            in: destinationTabs
        )
    }

    var placement: TabPlacement {
        destinationSection.placement
    }

    var folderID: FolderID? {
        destinationSection.folderID
    }

    func placing(_ tab: BrowserTab) -> BrowserTab {
        var placedTab = tab
        placedTab.placement = placement
        placedTab.folderID = folderID
        switch placement {
        case .current:
            placedTab.savedURL = nil
        case .pinned, .saved:
            placedTab.savedURL = placedTab.savedURL ?? placedTab.url
        }
        return placedTab
    }

    private static func resolvedFolderID(
        _ requestedFolderID: FolderID?,
        for placement: TabPlacement,
        in destinationSpace: BrowserSpace
    ) -> FolderID? {
        guard placement == .saved,
            let requestedFolderID,
            destinationSpace.folders.contains(where: { $0.id == requestedFolderID })
        else {
            return nil
        }
        return requestedFolderID
    }
}
