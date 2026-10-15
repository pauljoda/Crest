import SwiftUI

extension MobileBrowserRootContent {
    func selectTab(_ id: UUID) {
        dismissAddressFocus()
        let dismissesFloatingPhoneSidebar =
            presentation.dismissesSidebarOnTabSelection(
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
        presentation.beginNewTab(in: self)
    }

    func openLocation() {
        presentation.openLocation(in: self)
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
        guard presentation.presentsPageOverTabViewer else { return }
        guard compactTransition.commits(predictedEndTranslation: predictedEndTranslation) else { return }
        isAddressEditing = false
        compactTransition.finish(in: self)
    }

    /// Brings the sidebar up from the compact chrome's upward swipe, in the
    /// placement this window already keeps it in.
    ///
    /// `MobileCompactSidebarRevealDestination` carries the reasoning. The short of it
    /// is that the full-screen viewer is the docked sidebar, so a docked window
    /// goes on landing there, while an undocked one — which only has this
    /// toolbar to swipe because a split is on show — floats the sidebar over the
    /// split instead of dropping the split to reach it.
    func revealSidebarFromCompactChrome() {
        MobileCompactSidebarRevealDestination.destination(
            sidebarPresentation: navigation.regularSidebarPresentation
        )
        .reveal(in: self)
    }

    /// The compact toolbar's horizontal swipe.
    ///
    /// It used to switch Spaces unconditionally. As of 0.4 it belongs to Split
    /// View: `MobileToolbarSwipeMode` decides, and outside a group the answer
    /// is deliberately nothing. Keyboard Space switching (⌥⌘←/→) is untouched —
    /// it goes through `MobileBrowserCommandController`, not through here.
    func handleToolbarSwipe(_ direction: BrowserSpaceSwipeDirection) {
        MobileToolbarSwipeMode.shipping.destination(isInSplitGroup: isSelectedTabInSplitGroup)
            .swipe(direction, in: self)
    }

    /// The carousel's own selection commits: an accessibility adjustment, or a
    /// programmatic page that settled somewhere the selection did not expect.
    func selectSplitCard(_ tabID: UUID) {
        model.focusSplitCard(tabID)
    }

    var isSelectedTabInSplitGroup: Bool {
        model.presentedSplitGroupID != nil
    }

    func toggleSidebarFromCommand() {
        if presentation.presentsPageOverTabViewer, navigation.compactShowsPage {
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
