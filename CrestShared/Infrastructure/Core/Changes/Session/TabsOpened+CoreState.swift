import Foundation

extension TabsOpened {
    /// The tabs arrive through the `TabsChanged` before it; the window that
    /// opened them hears of it through `CrestCore.followOpenedTabs`.
    @MainActor func apply(to state: CoreState) {}

    @MainActor func apply(to core: CrestCore, in batch: inout CoreChangeBatch) {
        apply(to: core.state)
        batch.openedTabs.append(self)
    }
}
