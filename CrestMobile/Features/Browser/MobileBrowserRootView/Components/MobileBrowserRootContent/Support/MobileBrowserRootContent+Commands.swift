import Foundation

extension MobileBrowserRootContent {
    /// Whether the regular shell shows its overlay palette: one was asked for,
    /// over a selected tab the palette can act on.
    var isCommandPaletteShown: Bool {
        guard commandPaletteMode != nil, !presentation.presentsPageOverTabViewer,
            let source = browser.shownTabAssignment
        else {
            return false
        }
        return model.isPaletteSourceAvailable(source)
    }

    /// Which side of the field-to-palette morph holds the shared identity.
    /// Only the regular sidebar sits beside the overlay palette.
    var commandPaletteHandoff: BrowserCommandPaletteHandoff {
        .resolve(
            isPaletteShown: isCommandPaletteShown,
            isFieldOnScreen: navigation.regularSidebarIsPresented,
            animates: BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
        )
    }

    func presentArchiveFromCommand() {
        presentation.presentList(.archive, in: self)
    }

    func presentHistoryFromCommand() {
        presentation.presentList(.history, in: self)
    }

    func presentDownloadsFromCommand() {
        presentation.presentList(.downloads, in: self)
    }

    func dismissCommandPalette() {
        commandPaletteMode = nil
    }

    // MARK: - Search Mode

    /// Puts search up over the tab the window shows, the way the Search
    /// startup choice greets a person: the tab comes up behind it, and what
    /// they open from it goes to a new tab. A window that shows no tab, as a
    /// phone's after launch, shows its Space's tab used last first; one with
    /// none to show begins a new tab, whose field is search already.
    func presentSearch() {
        browser.showLastUsedTab()
        guard let source = browser.shownTabAssignment, model.isPaletteSourceAvailable(source) else {
            beginNewTab()
            return
        }
        guard !showsStartPage else {
            openLocation()
            return
        }
        searchOverShownTab()
    }

    /// The toolbar's New Tab while the Search startup choice is on: search
    /// comes up over the shown tab as it does on opening, and a Start Page
    /// takes the typing itself. Nil otherwise, which leaves the toolbar
    /// without the button.
    var newTabSearch: (() -> Void)? {
        guard BrowserAppPreferenceStore.shared.startupBehavior.presentsSearch else { return nil }
        return presentSearch
    }

    /// Search over the shown tab, which stays behind it; what is opened from
    /// it goes to a new tab.
    private func searchOverShownTab() {
        dismissAddressFocus()
        model.activateSelectedTab()
        // A narrow window's search rises from its address bar, so the bar
        // comes back first if scrolling put it away.
        navigation.showCompactToolbar()
        commandPaletteMode = .newTab
    }

    /// Puts search up by itself, as the window launches or for a person back
    /// after a while away, unless something else holds the window. False
    /// when something does.
    @discardableResult
    func presentAutomaticSearch() -> Bool {
        guard leavesWindowToAutomaticSearch else { return false }
        presentSearch()
        return true
    }

    /// Whether nothing else holds the window, so search may come up by
    /// itself: no palette or address edit is under way, no Settings, History,
    /// Downloads or utility is open, no Quick Window or Peek shows, no risky
    /// download waits for an answer, setup is not over the window, and the
    /// Space it shows is not locked. Search the person asks for goes by none
    /// of this.
    var leavesWindowToAutomaticSearch: Bool {
        let utilities = navigation.utilityPresentation
        let downloadQuestion = pages.downloadRiskConfirmation.request
        return commandPaletteMode == nil && !isAddressEditing
            && !model.showsSettings && browser.shownTab?.nativeTabContent != .settings
            && presentedListSheet == nil && downloadsAssignment == nil
            && utilities.surface == nil && !utilities.isSidebarInteractionActive
            && transientBrowsing.quickWindowRequest == nil && transientBrowsing.peekRequest == nil
            && !browser.spaceModels.contains { $0.profileID == downloadQuestion?.profileID }
            && !suspendsCompactPagePresentation && !model.selectedSpaceIsLocked
    }
}
