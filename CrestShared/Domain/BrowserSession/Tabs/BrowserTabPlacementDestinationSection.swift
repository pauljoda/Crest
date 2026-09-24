struct BrowserTabPlacementDestinationSection: Equatable, Sendable {
    let placement: TabPlacement
    let folderID: FolderID?

    func hasCapacity(in tabs: [BrowserTab]) -> Bool {
        guard let capacity = placement.capacity else { return true }
        return tabs.lazy.filter { $0.placement == placement }.count < capacity
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
        return tab.folderID == folderID
    }

    /// A section with no tabs yet starts where the next section does.
    private func emptySectionInsertionIndex(in tabs: [BrowserTab]) -> Int {
        tabs.firstIndex(where: { $0.placement.rank > placement.rank }) ?? tabs.endIndex
    }
}
