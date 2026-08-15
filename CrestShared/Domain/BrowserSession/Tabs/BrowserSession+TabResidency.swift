import Foundation

extension BrowserSession {
    @discardableResult
    mutating func setTabKeepsPageLoaded(
        _ keepsPageLoaded: Bool,
        tabID: TabID,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID }),
            let tabIndex = spaces[spaceIndex].tabs.firstIndex(where: { $0.id == tabID }),
            spaces[spaceIndex].tabs[tabIndex].keepsPageLoaded != keepsPageLoaded
        else { return false }
        spaces[spaceIndex].tabs[tabIndex].keepsPageLoaded = keepsPageLoaded
        return true
    }
}
