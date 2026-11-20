import Foundation

@testable import CrestMobile

extension MobileBrowserPageStore {
    /// Shows Space `spaceID` in the store's scene on the tab it last showed
    /// there, then presents what the scene shows.
    func present(space spaceID: UUID, at time: Date = .now) {
        browser.selectSpace(spaceID)
        select(at: time)
    }
}
