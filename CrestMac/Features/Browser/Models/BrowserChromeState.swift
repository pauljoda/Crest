import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserChromeState {
    var columnVisibility: NavigationSplitViewVisibility
    private(set) var commandPaletteMode: BrowserCommandPaletteMode?
    let utilityPresentation: BrowserUtilityPresentationState
    private(set) var addressFocusRequest = 0
    private(set) var startPageFocusRequest = 0
    private(set) var notice: BrowserNotice?
    private(set) var noticeRevision = 0

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
        commandPaletteMode = .editLocation(address)
    }

    func presentCommandPalette() {
        commandPaletteMode = .newTab
    }

    func openNewTab(isStartPageSelected: Bool) {
        guard isStartPageSelected else {
            presentCommandPalette()
            return
        }
        commandPaletteMode = nil
        startPageFocusRequest &+= 1
    }

    func dismissCommandPalette() {
        commandPaletteMode = nil
    }

    /// Shows `notice` at the top of this window, replacing any notice already
    /// there.
    func showNotice(_ notice: BrowserNotice) {
        self.notice = notice
        noticeRevision &+= 1
    }

    func showURLCopiedFeedback() {
        showNotice(.urlCopied)
    }

    func showPageZoomFeedback(_ label: String) {
        showNotice(.pageZoom(label))
    }

    func presentHistory() {
        utilityPresentation.present(.history)
    }
}
