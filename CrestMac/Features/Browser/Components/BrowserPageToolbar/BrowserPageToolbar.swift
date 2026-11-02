import SwiftUI

/// The back, forward, reload and address controls a page carries above itself
/// when the person keeps them there rather than in the sidebar.
///
/// Every card of a split carries its own. The focused card's controls act on
/// the window's shown tab and edit the window's address; another card's show
/// its own page and, when used, first bring that card forward.
struct BrowserPageToolbar: View {
    // MARK: - Types

    /// What the window hands every page's toolbar. Pages render in hosts of
    /// their own, so the window's environment does not reach them.
    struct Context {
        let model: BrowserRootModel
        /// The view an engine anchors its own popups to, which only the
        /// focused card's Site Controls carry.
        let siteControlAnchor: BrowserSiteControlAnchor?
    }

    // MARK: - Static Variables

    /// The room the toolbar keeps above and below its controls.
    static let verticalPadding: CGFloat = 4

    // MARK: - Variables

    let context: Context
    let tab: TabStateModel
    let space: SpaceModel
    let page: BrowserPage?

    /// Each toolbar keeps its field's identities to itself, so cards never
    /// trade them with one another or with the sidebar.
    @Namespace private var fieldNamespace

    private var model: BrowserRootModel { context.model }

    /// Whether this toolbar's tab is the one the window shows, as the page
    /// pool has it, which is what Split View highlights.
    private var isFocused: Bool {
        model.browser.selectedSpaceID == space.id && model.pages.activeTabID == tab.id
    }

    var body: some View {
        HStack(spacing: 0) {
            BrowserSidebarNavigationControls(port: navigationPort, capabilities: BrowserInteractionCapabilities())
                .fixedSize(horizontal: true, vertical: false)

            SpaceSidebarAddressBand(
                space: space,
                offersSiteControls: !model.browser.isDeleting(space.id),
                selectedTabID: tab.id,
                pages: model.pages,
                page: page,
                capabilities: BrowserInteractionCapabilities(),
                address: isFocused ? model.addressBinding : .constant(displayedAddress),
                isAddressEditing: isFocused ? model.isAddressEditingBinding : .constant(false),
                addressFocusRequest: isFocused ? model.chrome.addressFocusRequest : 0,
                activateAddress: activateAddress,
                submitAddress: model.submitAddress,
                commandSurfaceNamespace: fieldNamespace,
                commandPaletteHandoff: .neither,
                siteControlPresentationChanged: siteControlPresentationChanged,
                siteControlContextMenuPresentationChanged: {
                    model.chrome.utilityPresentation.setSiteControlContextMenuPresented($0)
                }
            )
            .environment(\.browserSiteControlAnchor, isFocused ? context.siteControlAnchor : nil)
        }
        .padding(.vertical, Self.verticalPadding)
        // The toolbar wears its Space's color, as the sidebar does, so its
        // controls read the same over any page.
        .background(space.settings.look.shown.primaryColor.color)
        .modifier(SpaceColorScheme(branding: space.settings.look))
        .modifier(SpaceForegroundBlend(spaces: model.browser.availableSpaces, selectedSpaceID: space.id))
    }

    /// What the field shows for a card that is not focused.
    private var displayedAddress: String {
        (page?.live.displayURL ?? tab.address)?.absoluteString ?? ""
    }

    /// The focused card drives the window's pool; another card drives its own
    /// page, and comes forward first.
    private var navigationPort: BrowserSidebarNavigationPort {
        let showHistory = { model.chrome.presentUtility(.history) }
        guard !isFocused else {
            return BrowserSidebarNavigationPort(pages: model.pages, browser: model.browser, showHistory: showHistory)
        }
        return BrowserSidebarNavigationPort(page: page, showHistory: showHistory) { [tabID = tab.id] in
            model.focusSplitCard(tabID)
        }
    }

    // MARK: - Actions - Site Controls

    /// Site Controls act for the window's shown tab, and an engine anchors its
    /// popups to the focused card's, so opening another card's brings that
    /// card forward first.
    private func siteControlPresentationChanged(_ isPresented: Bool) {
        if isPresented, !isFocused { model.focusSplitCard(tab.id) }
        model.chrome.utilityPresentation.setSiteControlPresented(isPresented)
    }

    // MARK: - Actions - Address

    /// Opens the location palette for this toolbar's tab, bringing its card
    /// forward first.
    private func activateAddress() {
        // Read before focusing: the window's address follows the newly
        // focused card only later.
        guard !isFocused else { return model.chrome.openLocation(model.address) }
        let address = displayedAddress
        model.focusSplitCard(tab.id)
        model.chrome.openLocation(address)
    }
}

extension EnvironmentValues {
    /// Set over a window's pages while the person keeps the address bar above
    /// them; nil leaves the controls in the sidebar.
    @Entry var browserPageToolbar: BrowserPageToolbar.Context? = nil
}
