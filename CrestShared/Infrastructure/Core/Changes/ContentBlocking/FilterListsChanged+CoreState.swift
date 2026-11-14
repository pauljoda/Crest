import Foundation

extension FilterListsChanged {
    @MainActor func apply(to state: CoreState) {
        state.filterLists = lists
    }
}
