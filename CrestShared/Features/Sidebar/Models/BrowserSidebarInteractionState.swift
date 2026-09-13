import Observation

/// Owns the interaction state shared by one window's sidebar and page surfaces.
@Observable
@MainActor
final class BrowserSidebarInteractionState: BrowserStoreInteractionObserving {
    let tabDragState = BrowserTabDragState()
    let folderDragState = BrowserFolderDragState()
    let sidebarReorderState = BrowserSidebarReorderState()

    // SwiftUI can evaluate a discarded root initializer while retaining the visible model.
    static func connected(to browser: BrowserStore) -> BrowserSidebarInteractionState {
        if let existing = browser.interactionObserver as? BrowserSidebarInteractionState { return existing }
        let interaction = BrowserSidebarInteractionState()
        browser.interactionObserver = interaction
        return interaction
    }

    private init() {}

    func cancel() {
        tabDragState.end()
        folderDragState.end()
        sidebarReorderState.cancel()
    }

    func browserWillResetSession() {
        cancel()
    }

    func browserDidMoveTab(from source: BrowserTabRuntimeAssignment, to destination: BrowserSpaceRuntimeAssignment) {
        guard tabDragState.isDragging(source) else { return }
        tabDragState.relocate(to: destination)
    }
}
