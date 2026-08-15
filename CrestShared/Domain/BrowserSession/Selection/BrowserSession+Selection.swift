import Foundation

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
              spaces.contains(where: { $0.id == defaultSpaceID }) else { return }
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
