import Foundation

extension TabsOpened {
    /// Opening changes no state of its own: the tabs arrive in the
    /// `TabsChanged` before it, and the window that opened them hears of it
    /// through `CrestCore.followOpenedTabs`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.openedTabs.append(self)
    }
}
