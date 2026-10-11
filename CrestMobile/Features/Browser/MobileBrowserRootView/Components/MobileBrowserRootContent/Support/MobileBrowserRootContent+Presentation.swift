import SwiftUI
import UIKit

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
        guard let space = browser.shownSpace, !spaceAccess.isLocked(space) else { return false }
        return model.presentedSplitMembers.count > 1
    }

    /// Whether the window shows the Start Page, or no tab at all.
    var showsStartPage: Bool {
        browser.shownTab.map { $0.surface == .startPage } ?? true
    }

    var usesBorderlessPageFrame: Bool {
        MobileSidebarPageFramePolicy.usesBorderlessFrame(
            preferenceIsEnabled: chromeAppearance.borderless,
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

    /// Whether Settings shows as a sheet from the page, which covers a
    /// narrow window while it shows, or from the window itself: a sheet asked
    /// of the window while the page covers it never appears.
    func settingsSheet(overPage: Bool) -> Binding<Bool> {
        Binding(
            get: {
                model.showsSettings
                    && (presentation == .compact && compactPagePresentation.wrappedValue) == overPage
            },
            set: { model.showsSettings = $0 }
        )
    }

    var settingsSheetContent: some View {
        MobileBrowserSettingsView(
            browser: browser, pages: pages, spaceAccess: spaceAccess, dataDeleter: dataDeleter,
            state: model.settings.state)
    }

    /// The expanded detail area. The container decides whether it adjoins a
    /// docked sidebar, while the page and split composition stay identical.
    func regularPageSurface(
        adjoinsSidebar: Bool,
        commands: BrowserCommandPaletteCommandRegistry
    ) -> MobileRegularPageSurface {
        MobileRegularPageSurface(
            model: model,
            adjoinsSidebar: adjoinsSidebar,
            usesBorderlessPageFrame:
                usesBorderlessPageFrame,
            address: model.addressBinding,
            isAddressEditing: $isAddressEditing,
            addressFocusRequest: addressFocusRequest,
            isCommandPalettePresented: commandPaletteMode != nil,
            commands: commands,
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
            usesPageToolbars: !MobileBrowserViewportPolicy.usesEdgeToEdgeWebViewport(
                isPhone: UIDevice.current.userInterfaceIdiom == .phone,
                presentation: presentation,
                sidebarPresentation: navigation.regularSidebarPresentation
            ),
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
