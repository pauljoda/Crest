import Foundation

@MainActor
protocol BrowserStoreInteractionObserving: AnyObject {
    func browserWillResetSession()
    func browserDidMoveTab(from source: BrowserTabRuntimeAssignment, to destination: BrowserSpaceRuntimeAssignment)
    func browserDidOpenBackgroundTab()
    func browserDidOpenTab(_ tabID: UUID, in spaceID: UUID)
}

extension BrowserStoreInteractionObserving {
    /// The desktop shell presents confirmation; other observers keep their native presentation.
    func browserDidOpenBackgroundTab() {}

    /// The desktop shell brings the tab's row into view; other observers leave their list where it is.
    func browserDidOpenTab(_ tabID: UUID, in spaceID: UUID) {}
}
