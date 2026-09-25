import Foundation

extension MobileBrowserRootContent {
    /// Whether the regular shell shows its overlay palette: one was asked for,
    /// over a selected tab the palette can act on.
    var isCommandPaletteShown: Bool {
        guard commandPaletteMode != nil, presentation == .regular,
            let space = browser.selectedSpace,
            let tabID = browser.selectedTab?.id
        else { return false }
        return model.isPaletteSourceAvailable(
            BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profile.id)
        )
    }

    /// Which side of the field-to-palette morph holds the shared identity.
    /// Only the regular sidebar sits beside the overlay palette.
    var commandPaletteHandoff: BrowserCommandPaletteHandoff {
        .resolve(
            isPaletteShown: isCommandPaletteShown,
            isFieldOnScreen: navigation.regularSidebarIsPresented,
            reduceMotion: reduceMotion
        )
    }

    func presentArchiveFromCommand() {
        model.revealSidebarForUtilityCommand(presentation: presentation)
        navigation.utilityPresentation.present(.archive)
    }

    func presentHistoryFromCommand() {
        switch presentation {
        case .compact:
            guard let space = browser.selectedSpace,
                BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                    matching: BrowserSpaceRuntimeAssignment(space: space),
                    in: browser,
                    accessController: spaceAccess
                ) != nil
            else { return }
            historyAssignment = BrowserSpaceRuntimeAssignment(space: space)
        case .regular:
            model.revealSidebarForUtilityCommand(presentation: presentation)
            navigation.utilityPresentation.present(.history)
        }
    }

    func presentDownloadsFromCommand() {
        model.revealSidebarForUtilityCommand(presentation: presentation)
        navigation.utilityPresentation.present(.downloads)
    }

    func dismissCommandPalette() {
        commandPaletteMode = nil
    }
}
