import Foundation

extension PageOpened {
    @MainActor func apply(to state: CoreState) {
        state.indexPage(page.id, from: state.pagesStorage[page.id]?.tabID, to: page.tabID)
        state.publish(PageStateModel(page), forKey: page.id, into: \.pagesStorage, as: \.pages)
    }
}
