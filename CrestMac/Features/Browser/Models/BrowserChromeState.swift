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
    /// Whether a page shows alone in full screen with the sidebar hover area
    /// still live, where a docked sidebar gives way to the edge reveal.
    var revealsSidebarOverFullscreenPage: Bool {
        get { observed(\.revealsSidebarOverFullscreenPageStorage, as: \.revealsSidebarOverFullscreenPage) }
        set {
            publish(newValue, into: \.revealsSidebarOverFullscreenPageStorage, as: \.revealsSidebarOverFullscreenPage)
        }
    }
    @ObservationIgnored private var revealsSidebarOverFullscreenPageStorage = false
    private(set) var commandPaletteMode: BrowserCommandPaletteMode? {
        get { observed(\.commandPaletteModeStorage, as: \.commandPaletteMode) }
        set { publish(newValue, into: \.commandPaletteModeStorage, as: \.commandPaletteMode) }
    }
    @ObservationIgnored private var commandPaletteModeStorage: BrowserCommandPaletteMode?
    /// What the person has entered in the open new-tab palette: the text and
    /// the search provider or scope they narrowed it to. A palette opened
    /// again for another Space starts from it, so all of it follows them
    /// there.
    @ObservationIgnored private(set) var newTabDraft = BrowserCommandPaletteDraft.empty
    private(set) var addressFocusRequest = 0
    private(set) var startPageFocusRequest = 0
    private(set) var notice: BrowserNotice?
    private(set) var noticeRevision: Int {
        get { observed(\.noticeRevisionStorage, as: \.noticeRevision) }
        set { publish(newValue, into: \.noticeRevisionStorage, as: \.noticeRevision) }
    }
    @ObservationIgnored private var noticeRevisionStorage = 0
    /// The recent tabs a held Most Recent Tab shortcut shows over the window,
    /// or nil while none shows.
    var recentTabs: RecentTabSwitcherModel? {
        get { observed(\.recentTabsStorage, as: \.recentTabs) }
        set {
            guard recentTabsStorage !== newValue else { return }
            recentTabsStorage = newValue
            withMutation(keyPath: \.recentTabs) {}
        }
    }
    @ObservationIgnored private var recentTabsStorage: RecentTabSwitcherModel?

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

    /// Hiding cancels utility presentation and pending input before an asynchronous view update can mount it.
    func hideSidebar() {
        utilityPresentation.dismiss()
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

    /// Utility shortcuts preserve the docked preference and toggle a floating sidebar when hidden.
    func toggleUtility(_ surface: BrowserUtilitySurface) {
        if utilityPresentation.surface == surface,
            columnVisibility != .detailOnly || isFloatingSidebarPresented
        {
            utilityPresentation.dismiss(surface)
            if columnVisibility == .detailOnly {
                isFloatingSidebarPresented = false
            }
        } else {
            if columnVisibility == .detailOnly {
                isFloatingSidebarPresented = true
            }
            presentUtility(surface)
        }
    }

    func handleWebContentInteraction() {
        guard columnVisibility != .detailOnly || !isFloatingSidebarPresented else { return }
        utilityPresentation.handleInteraction(.webContent)
    }

    // MARK: - Actions - Command Palette

    func openLocation(_ address: String = "") {
        newTabDraft = .empty
        commandPaletteMode = .editLocation(address)
    }

    func presentCommandPalette() {
        newTabDraft = .empty
        commandPaletteMode = .newTab
    }

    /// What a palette opened in `mode` starts from: what was entered in the
    /// new-tab palette so far, or nil for an edited tab's address, which
    /// starts from that address.
    func commandPaletteDraft(for mode: BrowserCommandPaletteMode) -> BrowserCommandPaletteDraft? {
        mode == .newTab ? newTabDraft : nil
    }

    /// Notes what the person entered while the new-tab palette is open.
    func recordCommandPaletteDraft(_ draft: BrowserCommandPaletteDraft) {
        guard commandPaletteMode == .newTab else { return }
        newTabDraft = draft
    }

    /// The window moved to another Space. A new tab can open there just as
    /// well, so its palette stays open with what was typed; editing an
    /// address belongs to the tab left behind, so that palette closes.
    func spaceChanged() {
        guard case .editLocation = commandPaletteMode else { return }
        dismissCommandPalette()
    }

    func openNewTab(isStartPageSelected: Bool) {
        // A Start Page closes the command bar into its own field below.
        if isCommandPalettePresented, !isStartPageSelected {
            dismissCommandPalette()
            return
        }
        guard isStartPageSelected else {
            presentCommandPalette()
            return
        }
        dismissCommandPalette()
        startPageFocusRequest &+= 1
    }

    func dismissCommandPalette() {
        newTabDraft = .empty
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
