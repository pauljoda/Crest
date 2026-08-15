struct BrowserTabPlacementDestinationSection: Equatable, Sendable {
    let placement: TabPlacement
    let folderID: FolderID?

    func hasCapacity(in tabs: [BrowserTab]) -> Bool {
        guard placement == .pinned else { return true }
        return tabs.lazy.filter { $0.placement == .pinned }.count
            < BrowserSpace.maximumPinnedTabs
    }

    func insertionIndex(
        before destinationTabID: TabID?,
        in tabs: [BrowserTab]
    ) -> Int {
        if let destinationTabID,
            let targetIndex = tabs.firstIndex(where: {
                $0.id == destinationTabID && contains($0)
            })
        {
            return targetIndex
        }
        if let lastMatchingIndex = tabs.lastIndex(where: contains) {
            return tabs.index(after: lastMatchingIndex)
        }
        return emptySectionInsertionIndex(in: tabs)
    }

    func contains(_ tab: BrowserTab) -> Bool {
        guard tab.placement == placement else { return false }
        return placement != .saved || tab.folderID == folderID
    }

    private func emptySectionInsertionIndex(in tabs: [BrowserTab]) -> Int {
        switch placement {
        case .pinned:
            return tabs.firstIndex(where: { $0.placement != .pinned })
                ?? tabs.endIndex
        case .saved:
            return tabs.firstIndex(where: { $0.placement == .current })
                ?? tabs.endIndex
        case .current:
            return tabs.endIndex
        }
    }
}
