import Foundation

extension PageRemoved {
    @MainActor func apply(to state: CoreState) {
        state.indexPage(pageID, from: state.pagesStorage[pageID]?.tabID, to: nil)
        state.publish(nil, forKey: pageID, into: \.pagesStorage, as: \.pages)
    }
}
