import Observation
import SwiftUI

// MARK: - Types

/// A page of Site Controls a command asked to show for one page.
struct BrowserSiteControlsRequest: Equatable {
    /// The page whose Site Controls open.
    let page: ObjectIdentifier
    let destination: SiteControlsPage
    /// Tells two requests for the same page apart, so asking again opens it
    /// again.
    let id = UUID()
}

@Observable
@MainActor
final class BrowserChromeState {
    // MARK: - Variables

    let utilityPresentation: BrowserUtilityPresentationState
    /// The notice this window shows at its top.
    let notices = BrowserNotices()
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
    private(set) var addressFocusRequest = 0
    /// The page of Site Controls a command asked to show, such as Show QR
    /// Code, which the Site Controls of the page it names open on.
    private(set) var siteControlsRequest: BrowserSiteControlsRequest?
    private(set) var startPageFocusRequest = 0
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

    /// Whether the palette is open to edit the shown tab's address.
    var isEditingLocation: Bool {
        guard case .editLocation = commandPaletteMode else { return false }
        return true
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
        commandPaletteMode = .editLocation(address)
    }

    /// Edits `address`, or puts the editor away when it is already showing,
    /// as pressing Open Location's keys again does.
    func toggleLocation(_ address: String) {
        if isEditingLocation {
            dismissCommandPalette()
        } else {
            openLocation(address)
        }
    }

    func presentCommandPalette() {
        commandPaletteMode = .newTab
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
        commandPaletteMode = nil
        startPageFocusRequest &+= 1
    }

    func dismissCommandPalette() {
        commandPaletteMode = nil
    }

    // MARK: - Actions - Site Controls

    /// Asks the Site Controls of `page` to open on `destination`.
    func requestSiteControls(_ destination: SiteControlsPage, for page: BrowserPage) {
        siteControlsRequest = BrowserSiteControlsRequest(page: ObjectIdentifier(page), destination: destination)
    }

    /// The page of Site Controls asked for `page`, which only its Site
    /// Controls take, once; nil when none was asked for it.
    func takeSiteControlsRequest(for page: BrowserPage) -> SiteControlsPage? {
        guard let request = siteControlsRequest, request.page == ObjectIdentifier(page) else { return nil }
        siteControlsRequest = nil
        return request.destination
    }

    // MARK: - Actions - Notices

    /// Shows `notice` at the top of this window, replacing any notice already
    /// there.
    func showNotice(_ notice: BrowserNotice) {
        notices.show(notice)
    }

    func showURLCopiedFeedback() {
        showNotice(.urlCopied)
    }

    func showPageZoomFeedback(_ label: String) {
        showNotice(.pageZoom(label))
    }
}

extension BrowserChromeState: BrowserStoreFirstObservable {}
