import Foundation

extension ContentRuleListsChanged {
    @MainActor func apply(to state: CoreState) {
        state.contentRuleLists = lists
    }
}
