import SwiftUI
import UIKit

extension MobileBrowserRootContent {
    var browser: BrowserStore { model.browser }
    var pages: MobileBrowserPageStore { model.pages }
    var navigation: MobileBrowserNavigationState { model.navigation }
    var spaceAccess: BrowserSpaceAccessController { model.spaceAccess }
    var address: String { model.address }

    var presentation: MobileBrowserPresentation {
        UIDevice.current.userInterfaceIdiom == .phone ? .compact : .regular
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

    /// The iPad detail area, built once for the side-by-side layout and once for
    /// the overlay layout. The two differ only in whether the row adjoins a
    /// docked sidebar, so everything else is assembled here rather than twice.
    func regularPageSurface(
        adjoinsLeadingSidebar: Bool
    ) -> MobileRegularPageSurface {
        MobileRegularPageSurface(
            model: model,
            adjoinsLeadingSidebar: adjoinsLeadingSidebar,
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
