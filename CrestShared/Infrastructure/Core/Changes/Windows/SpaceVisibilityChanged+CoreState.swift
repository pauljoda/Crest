import Foundation

extension SpaceVisibilityChanged {
    @MainActor func apply(to state: CoreState) {
        state.spaceVisibility = visibility
    }
}
