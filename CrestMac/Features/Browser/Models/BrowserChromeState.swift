import Observation
import SwiftUI

@Observable
@MainActor
final class BrowserChromeState {
    // MARK: - Variables

    let utilityPresentation: BrowserUtilityPresentationState
    var columnVisibility: NavigationSplitViewVisibility {
        get { observed(\.columnVisibilityStorage, as: \.columnVisibility) }
        set { publish(newValue, into: \.columnVisibilityStorage, as: \.columnVisibility) }
    }
    @ObservationIgnored private var columnVisibilityStorage: NavigationSplitViewVisibility
    /// Whether the undocked sidebar is floating over the page, as it does while
    /// the pointer rests at the window's edge.
    var isFloatingSidebarPresented: Bool {
        get { observed(\.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
        set { publish(newValue, into: \.isFloatingSidebarPresentedStorage, as: \.isFloatingSidebarPresented) }
    }
    @ObservationIgnored private var isFloatingSidebarPresentedStorage = false
    private(set) var commandPaletteMode: BrowserCommandPaletteMode? {
        get { observed(\.commandPaletteModeStorage, as: \.commandPaletteMode) }
        set { publish(newValue, into: \.commandPaletteModeStorage, as: \.commandPaletteMode) }
    }
    @ObservationIgnored private var commandPaletteModeStorage: BrowserCommandPaletteMode?
    private(set) var addressFocusRequest = 0
    private(set) var startPageFocusRequest = 0
    private(set) var notice: BrowserNotice?
    private(set) var noticeRevision: Int {
        get { observed(\.noticeRevisionStorage, as: \.noticeRevision) }
        set { publish(newValue, into: \.noticeRevisionStorage, as: \.noticeRevision) }
    }
    @ObservationIgnored private var noticeRevisionStorage = 0

    var isCommandPalettePresented: Bool {
        commandPaletteMode != nil
    }

    // MARK: - Initializers

    init(
        sidebarIsPresented: Bool = true,
        utilityPresentation: BrowserUtilityPresentationState =
            BrowserUtilityPresentationState()
    ) {
        columnVisibilityStorage = sidebarIsPresented ? .all : .detailOnly
        self.utilityPresentation = utilityPresentation
    }

    // MARK: - Actions - Sidebar

    func hideSidebar() {
        columnVisibility = .detailOnly
    }

    func showSidebar() {
        columnVisibility = .all
    }

    /// Brings `surface` up in the sidebar. Every route to History, Archive and
    /// Downloads comes through here, so none can open its list in a sidebar no
    /// one can see: a hidden sidebar docks first, and one floating over the
    /// page keeps floating.
    func presentUtility(_ surface: BrowserUtilitySurface) {
        if columnVisibility == .detailOnly, !isFloatingSidebarPresented {
            showSidebar()
        }
        utilityPresentation.present(surface)
    }

    // MARK: - Actions - Command Palette

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

    // MARK: - Actions - Notices

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
}

extension BrowserChromeState: BrowserStoreFirstObservable {}
