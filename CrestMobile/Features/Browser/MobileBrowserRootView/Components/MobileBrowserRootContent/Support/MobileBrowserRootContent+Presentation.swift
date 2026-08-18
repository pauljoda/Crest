import SwiftUI

extension MobileBrowserRootContent {
    var browser: BrowserStore { model.browser }
    var pages: MobileBrowserPageStore { model.pages }
    var navigation: MobileBrowserNavigationState { model.navigation }
    var spaceAccess: BrowserSpaceAccessController { model.spaceAccess }
    var address: String { model.address }

    var presentation: MobileBrowserPresentation {
        MobileBrowserPresentationPolicy.resolve(
            availableWidth: availableRootSize.width
        )
    }

    var presentsSplitView: Bool {
        guard let space = browser.selectedSpace,
            !spaceAccess.isLocked(space)
        else { return false }
        return model.presentedSplitMembers.count > 1
    }

    var usesCollapsedSidebarBorderlessFrame: Bool {
        MobileSidebarPageFramePolicy.usesBorderlessFrame(
            preferenceIsEnabled: collapsedSidebarFullscreenIsEnabled,
            sidebarPresentation: navigation.regularSidebarPresentation,
            presentsSplitView: presentsSplitView,
            browserPresentation: presentation
        )
    }

    var showsCompactPageToolbar: Bool {
        MobileSidebarPageFramePolicy.showsCompactToolbar(
            sidebarPresentation: navigation.regularSidebarPresentation,
            presentsSplitView: presentsSplitView
        )
    }

    var ignoresFloatingKeyboardSafeArea: Bool {
        MobileKeyboardLayoutPolicy.isFloating(
            keyboardFrame: keyboardEndFrame,
            availableSize: availableRootSize
        )
    }

    var compactPagePresentation: Binding<Bool> {
        Binding(
            get: {
                navigation.compactShowsPage
                    && !suspendsCompactPagePresentation
            },
            set: { isPresented in
                guard !suspendsCompactPagePresentation else { return }
                if isPresented {
                    navigation.selectTab()
                } else {
                    navigation.dismissPageToTabViewer()
                }
            }
        )
    }

    /// The expanded detail area. The container decides whether it adjoins a
    /// docked sidebar, while the page and split composition stay identical.
    func regularPageSurface(
        adjoinsLeadingSidebar: Bool
    ) -> MobileRegularPageSurface {
        MobileRegularPageSurface(
            model: model,
            adjoinsLeadingSidebar: adjoinsLeadingSidebar,
            usesCollapsedSidebarBorderlessFrame:
                usesCollapsedSidebarBorderlessFrame,
            address: model.addressBinding,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            isCommandPalettePresented: commandPaletteMode != nil,
            compactToolbarIsHidden: navigation.compactToolbarIsHidden,
            submitAddress: submitAddress,
            beginNewTab: beginNewTab,
            showTabViewer: showTabViewer,
            hideCompactToolbar: navigation.hideCompactToolbar,
            showCompactToolbar: navigation.showCompactToolbar,
            handleToolbarSwipe: handleToolbarSwipe,
            selectSplitCard: selectSplitCard,
            compactTransitionEnded: finishCompactTransition
        )
    }

    var compactTransition: MobileCompactChromeTransition {
        navigation.compactShowsPage ? .revealTabViewer : .revealPage
    }

    var mobileBrowserCommandContext: MobileBrowserCommandContext {
        model.commandContext(
            transientBrowsing: transientBrowsing,
            layoutDirection: layoutDirection,
            togglePrivateBrowsing: togglePrivateBrowsing,
            openNewTab: beginNewTab,
            openLocation: openLocation,
            prepareForSelectionSynchronization: dismissAddressFocus,
            toggleSidebar: toggleSidebarFromCommand,
            presentHistory: presentHistoryFromCommand,
            presentArchive: presentArchiveFromCommand,
            presentDownloads: presentDownloadsFromCommand
        )
    }
}
