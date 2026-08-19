import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserChromeState {
    var columnVisibility: NavigationSplitViewVisibility
    private(set) var commandPaletteMode: BrowserCommandPaletteMode?
    let utilityPresentation: BrowserUtilityPresentationState
    private(set) var addressFocusRequest = 0
    private(set) var urlCopyFeedbackRevision = 0
    private(set) var pageZoomFeedbackLabel = "100%"
    private(set) var pageZoomFeedbackRevision = 0

    var isCommandPalettePresented: Bool {
        commandPaletteMode != nil
    }

    init(
        sidebarIsPresented: Bool = true,
        utilityPresentation: BrowserUtilityPresentationState =
            BrowserUtilityPresentationState()
    ) {
        columnVisibility = sidebarIsPresented ? .all : .detailOnly
        self.utilityPresentation = utilityPresentation
    }

    func hideSidebar() {
        columnVisibility = .detailOnly
    }

    func showSidebar() {
        columnVisibility = .all
    }

    func openLocation(_ address: String = "") {
        showSidebar()
        commandPaletteMode = .editLocation(address)
    }

    func presentCommandPalette() {
        commandPaletteMode = .newTab
    }

    func dismissCommandPalette() {
        commandPaletteMode = nil
    }

    func showURLCopiedFeedback() {
        urlCopyFeedbackRevision &+= 1
    }

    func showPageZoomFeedback(_ label: String) {
        pageZoomFeedbackLabel = label
        pageZoomFeedbackRevision &+= 1
    }

    func presentHistory() {
        utilityPresentation.present(.history)
    }
}
