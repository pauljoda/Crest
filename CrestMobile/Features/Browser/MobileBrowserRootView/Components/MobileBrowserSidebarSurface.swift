import SwiftUI

/// The compact shell's sidebar adapter: it resolves what this placement can do,
/// binds the sidebar's ports to the compact page store, and owns the sheets the
/// chrome asks for.
///
/// One shell puts the sidebar on screen three ways — filling the window as the
/// tab viewer, floating over a page, and docked beside one — and each way makes
/// its own choices about where the utility lists come up, whether the pager
/// paints its own ground, and whether the bottom inset is held open. Those
/// arrive as separate values rather than as one mode, because nothing under here
/// should be able to ask which of the three it is.
struct MobileBrowserSidebarSurface: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let dataDeleter: any BrowserSpaceDataDeleting
    let spaceAccess: BrowserSpaceAccessController

    /// Where the archive, history, and downloads lists come up.
    let utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle

    /// Whether each Space's page paints the Space's own branded ground, which a
    /// sidebar filling the window needs and one over a page does not.
    let showsPageBackdrop: Bool

    /// Whether the bottom inset is held open even while its controls are gone,
    /// which is what keeps a matched tab destination at one resting position.
    let reservesBottomChromeInset: Bool

    /// Whether the selected Space's page stays on screen beside the sidebar.
    let presentsSelectedSpacePage: Bool

    /// Whether the sidebar toggle detaches the sidebar rather than hiding or
    /// docking it.
    let sidebarToggleUndocks: Bool

    /// Whether selecting a tab zooms its page in with the system's own
    /// navigation transition.
    let usesNativeNavigationTransition: Bool

    let compactChromeNamespace: Namespace.ID
    let tabPromotionNamespace: Namespace.ID
    @Binding var address: String
    @Binding var isAddressEditing: Bool
    let activateAddress: () -> Void
    let selectTab: (TabID) -> Void
    let submitAddress: () -> Void
    let openURL: (URL) -> Void
    let openNewTab: () -> Void
    let showsCompactAddressBar: Bool
    let showsBottomSpaceSwitcher: Bool
    let compactPageIsFullyPresented: Bool
    let compactTransitionEnded: (CGSize) -> Void
    let togglePrivateBrowsing: () -> Void
    let closePrivateBrowsing: () -> Void
    let toggleSidebar: () -> Void
    let showsSidebarToggle: Bool
    let sidebarIsPresented: Bool
    let sidebarIsDocked: Bool
    let utilityPresentation: BrowserUtilityPresentationState

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsPasswords = false
    @State private var showsSettings = false
    @State private var presentedSpaceSheet: MobileBrowserSidebarSpaceSheet?

    var body: some View {
        MobileBrowserSidebarPresentation(configuration: presentation) {
            BrowserSidebar(
                browser: browser,
                pageAccess: pageAccess,
                spaceAccess: spaceAccess,
                capabilities: capabilities,
                utilityCoordinator: utilityCoordinator,
                utilityPresentation: utilityPresentation,
                chromeActions: chromeActions,
                presentsSelectedSpacePage: presentsSelectedSpacePage,
                spaceSelectionChanged: synchronizeAddress(for:)
            ) { context in
                MobileBrowserSidebarContent(
                    configuration: contentConfiguration(context)
                )
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    /// What this shell can do: a finger is the primary input, a trackpad may
    /// still be attached, the sections draw their drop feedback on the rows, and
    /// only the placement that pushes a page has a transition to zoom with.
    ///
    /// Nothing here grows out of a row through a matched-geometry pairing. The
    /// placement that pushes a page joins the row through the system's zoom
    /// instead; the two that keep the page on screen the whole time join nothing
    /// at all. Saying so is what keeps a partnerless anchor off the view the
    /// reorder lift is dragged from.
    private var capabilities: BrowserInteractionCapabilities {
        BrowserInteractionCapabilities(
            supportsHover: true,
            supportsTouch: true,
            showsRowDropIndicators: true,
            reservesReorderSectionZones: true,
            usesNativeNavigationTransition: usesNativeNavigationTransition,
            pairsRowWithPromotedSurface: false
        )
    }

    private var pageAccess: BrowserSidebarPageAccess {
        BrowserSidebarPageAccess(pages: pages, browser: browser)
    }

    private var utilityCoordinator: BrowserSidebarUtilityCoordinator {
        BrowserSidebarUtilityCoordinator(
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            selectTab: selectTab,
            openURL: openURL
        )
    }

    private var chromeActions: BrowserSidebarChromeActions {
        BrowserSidebarChromeActions(
            presentSpaceSettings: { _ in showsSettings = true },
            presentHistory: presentHistory,
            presentPasswords: { showsPasswords = true },
            presentArchive: { presentSpaceSheet(.archive) },
            presentDownloads: { presentSpaceSheet(.downloads) }
        )
    }

    private var presentation: MobileBrowserSidebarPresentationConfiguration {
        MobileBrowserSidebarPresentationConfiguration(
            browser: browser,
            pages: pages,
            dataDeleter: dataDeleter,
            spaceAccess: spaceAccess,
            selectedColorScheme: selectedSidebarColorScheme,
            showsPasswords: $showsPasswords,
            showsSettings: $showsSettings,
            presentedSpaceSheet: $presentedSpaceSheet,
            selectedSpaceAssignment: selectedSpaceAssignment,
            selectTab: selectTab,
            openURL: openURL
        )
    }

    private func contentConfiguration(
        _ context: BrowserSidebarContext
    ) -> MobileBrowserSidebarContentConfiguration {
        MobileBrowserSidebarContentConfiguration(
            context: context,
            pages: pages,
            compactChromeNamespace: compactChromeNamespace,
            tabPromotionNamespace: tabPromotionNamespace,
            address: $address,
            isAddressEditing: $isAddressEditing,
            spaceActionsConfiguration: spaceActionsConfiguration(context),
            utilityPresentationStyle: utilityPresentationStyle,
            showsPageBackdrop: showsPageBackdrop,
            reservesBottomChromeInset: reservesBottomChromeInset,
            sidebarToggleUndocks: sidebarToggleUndocks,
            activateAddress: activateAddress,
            selectTab: selectTab,
            submitAddress: submitAddress,
            openNewTab: openNewTab,
            showsCompactAddressBar: showsCompactAddressBar,
            showsBottomSpaceSwitcher: showsBottomSpaceSwitcher,
            compactPageIsFullyPresented: compactPageIsFullyPresented,
            compactTransitionEnded: compactTransitionEnded,
            closePrivateBrowsing: closePrivateBrowsing,
            toggleSidebar: toggleSidebar,
            showsSidebarToggle: showsSidebarToggle,
            sidebarIsPresented: sidebarIsPresented,
            sidebarIsDocked: sidebarIsDocked
        )
    }

    private func spaceActionsConfiguration(
        _ context: BrowserSidebarContext
    ) -> MobileSpaceActionsConfiguration {
        MobileSpaceActionsConfiguration(
            showSettings: { showsSettings = true },
            showArchive: { context.chromeActions.presentArchive?() },
            showDownloads: { context.chromeActions.presentDownloads?() },
            commonListsAreExpanded: utilityPresentation.isSwitcherExpanded,
            toggleCommonLists: context.toggleUtilitySwitcher,
            recordCommonListsTriggerFrame:
                utilityPresentation.recordTriggerFrame,
            togglePrivateBrowsing: togglePrivateBrowsing
        )
    }

    private var selectedSidebarColorScheme: ColorScheme {
        guard MobileBrowserSidebarAppearancePolicy.usesSpaceForeground(),
            let space = browser.selectedSpace
        else { return colorScheme }
        return BrowserSpaceForegroundPolicy.colorScheme(for: space.branding)
    }

    private var selectedSpaceAssignment: BrowserSpaceRuntimeAssignment? {
        browser.selectedSpace.map(BrowserSpaceRuntimeAssignment.init(space:))
    }

    private func presentHistory() {
        switch utilityPresentationStyle {
        case .inline:
            utilityPresentation.present(.history)
        case .sheet:
            presentSpaceSheet(.history)
        }
    }

    /// Puts one of the Space's lists up as a sheet, and refuses unless the Space
    /// is still the selected, unlocked one the sheet would be about.
    private func presentSpaceSheet(_ surface: BrowserUtilitySurface) {
        guard utilityPresentationStyle == .sheet,
            let assignment = selectedSpaceAssignment,
            BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment,
                in: browser,
                accessController: spaceAccess
            ) != nil
        else { return }
        presentedSpaceSheet = MobileBrowserSidebarSpaceSheet(
            surface: surface,
            assignment: assignment
        )
        if surface == .downloads {
            pages.downloadCenter.acknowledgeItems(for: assignment.profileID)
        }
    }

    /// Brings the address field back in step once the session has moved.
    ///
    /// This shell owns the field, so it is the one that has to answer for it: a
    /// locked or vanished Space empties it, a placement that shows the page next
    /// to the sidebar takes the new Space's URL, and editing always ends because
    /// whatever was being typed belonged to the Space that was left.
    private func synchronizeAddress(for space: BrowserSpace?) {
        if space == nil {
            address = ""
        } else if presentsSelectedSpacePage {
            address = browser.selectedTab?.url?.absoluteString ?? ""
        }
        isAddressEditing = false
    }
}

#Preview("Mobile Browser Sidebar") {
    @Previewable @Namespace var compactChromeNamespace
    @Previewable @Namespace var tabPromotionNamespace
    @Previewable @State var address = ""
    @Previewable @State var isAddressEditing = false
    let fixture = MobileBrowserSidebarPreviewFixture()

    MobileBrowserSidebarSurface(
        browser: fixture.browser,
        pages: fixture.pages,
        dataDeleter: fixture.pages,
        spaceAccess: fixture.spaceAccess,
        utilityPresentationStyle: .inline,
        showsPageBackdrop: false,
        reservesBottomChromeInset: false,
        presentsSelectedSpacePage: true,
        sidebarToggleUndocks: false,
        usesNativeNavigationTransition: false,
        compactChromeNamespace: compactChromeNamespace,
        tabPromotionNamespace: tabPromotionNamespace,
        address: $address,
        isAddressEditing: $isAddressEditing,
        activateAddress: {},
        selectTab: { _ in },
        submitAddress: {},
        openURL: { _ in },
        openNewTab: {},
        showsCompactAddressBar: false,
        showsBottomSpaceSwitcher: true,
        compactPageIsFullyPresented: false,
        compactTransitionEnded: { _ in },
        togglePrivateBrowsing: {},
        closePrivateBrowsing: {},
        toggleSidebar: {},
        showsSidebarToggle: true,
        sidebarIsPresented: true,
        sidebarIsDocked: true,
        utilityPresentation: BrowserUtilityPresentationState()
    )
}
