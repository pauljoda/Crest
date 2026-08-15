import Foundation

extension BrowserSession {
    var selectedSpaceIndex: Int? {
        spaces.firstIndex { $0.id == selectedSpaceID }
    }

    var selectedTabIndices: (space: Int, tab: Int)? {
        guard let spaceIndex = selectedSpaceIndex else { return nil }
        guard let tabID = spaces[spaceIndex].selectedTabID else { return nil }
        guard let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }) else { return nil }
        return (spaceIndex, tabIndex)
    }

    mutating func ensureSelection(in spaceID: SpaceID) {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        guard spaces[index].selectedTabID.map(spaces[index].contains) != true else { return }
        spaces[index].selectedTabID = spaces[index].currentTabs.first?.id
            ?? spaces[index].pinnedTabs.first?.id
            ?? spaces[index].savedTabs.first?.id
    }

}
