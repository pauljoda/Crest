import SwiftUI

extension MobileBrowserRootContent {
    func selectTab(_ id: TabID) {
        dismissAddressFocus()
        let dismissesFloatingPhoneSidebar =
            MobileSidebarTabSelectionPolicy.dismissesSidebar(
                browserPresentation: presentation,
                sidebarPresentation: navigation.regularSidebarPresentation
            )
        model.selectTab(id)
        if dismissesFloatingPhoneSidebar {
            hideRegularSidebar()
        }
    }

    func submitAddress() {
        guard model.submitAddress() else { return }
        isAddressEditing = false
    }

    func openURL(_ url: URL) {
        model.openURL(url)
    }

    func beginNewTab() {
        if presentation == .compact {
            model.beginCompactNewTab()
            isAddressEditing = false
            addressFocusRequest &+= 1
        } else {
            switch MobileStartPageSearchPolicy.destination(
                isStartPage: browser.selectedTab?.isStartPage == true,
                presentation: presentation
            ) {
            case .embeddedStartPage:
                focusStartPageCommandPalette()
            case .overlay:
                commandPaletteMode = .newTab
            }
        }
    }

    func openLocation() {
        if presentation == .compact {
            if navigation.defersPageActivation {
                model.activateSelectedTab()
            }
            Task { @MainActor in
                await Task.yield()
                isAddressEditing = true
                addressFocusRequest &+= 1
            }
            return
        }

        showRegularSidebar()
        switch MobileStartPageSearchPolicy.destination(
            isStartPage: browser.selectedTab?.isStartPage == true,
            presentation: presentation
        ) {
        case .embeddedStartPage:
            focusStartPageCommandPalette()
        case .overlay:
            commandPaletteMode = .editLocation(address)
        }
    }

    func focusStartPageCommandPalette() {
        model.focusStartPageAddress()
        isAddressEditing = false
        addressFocusRequest &+= 1
    }

    func showTabViewer() {
        dismissAddressFocus()
        model.showTabViewer()
    }

    func finishCompactTransition(_ predictedEndTranslation: CGSize) {
        guard presentation == .compact else { return }
        guard
            MobileCompactChromeTransitionPolicy.commits(
                predictedEndTranslation: predictedEndTranslation,
                for: compactTransition
            )
        else { return }
        isAddressEditing = false
        switch compactTransition {
        case .revealTabViewer:
            showTabViewer()
        case .revealPage:
            model.activateSelectedTab()
        }
    }

    /// The compact toolbar's horizontal swipe.
    ///
    /// It used to switch Spaces unconditionally. As of 0.4 it belongs to Split
    /// View: `MobileToolbarSwipePolicy` decides, and outside a group the answer
    /// is deliberately nothing. Keyboard Space switching (⌥⌘←/→) is untouched —
    /// it goes through `MobileBrowserCommandController`, not through here.
    func handleToolbarSwipe(_ direction: BrowserSpaceSwipeDirection) {
        switch MobileToolbarSwipePolicy.destination(
            isInSplitGroup: isSelectedTabInSplitGroup
        ) {
        case .adjacentCard:
            model.selectAdjacentSplitCard(direction)
        case .adjacentSpace:
            model.switchSpace(direction, reduceMotion: reduceMotion)
        case .none:
            break
        }
    }

    /// The carousel's own selection commits: an accessibility adjustment, or a
    /// programmatic page that settled somewhere the selection did not expect.
    func selectSplitCard(_ tabID: TabID) {
        model.focusSplitCard(tabID)
    }

    var isSelectedTabInSplitGroup: Bool {
        guard let space = browser.selectedSpace,
            let selectedTabID = space.selectedTabID
        else { return false }
        return space.splitGroup(containing: selectedTabID) != nil
    }

    func toggleSidebarFromCommand() {
        if presentation == .compact, navigation.compactShowsPage {
            dismissAddressFocus()
        }
        model.toggleSidebar(
            presentation: presentation,
            reduceMotion: reduceMotion
        )
    }

    func hideRegularSidebar() {
        model.hideRegularSidebar(reduceMotion: reduceMotion)
    }

    func showRegularSidebar() {
        model.showRegularSidebar(reduceMotion: reduceMotion)
    }

    func toggleRegularSidebar() {
        model.toggleSidebar(
            presentation: .regular,
            reduceMotion: reduceMotion
        )
    }

    func toggleCompactSidebar() {
        dismissAddressFocus()
        model.toggleSidebar(
            presentation: .compact,
            reduceMotion: reduceMotion
        )
    }

    func dismissAddressFocus() {
        isAddressEditing = false
        BrowserAddressFocusDismissal.dismiss()
    }
}
