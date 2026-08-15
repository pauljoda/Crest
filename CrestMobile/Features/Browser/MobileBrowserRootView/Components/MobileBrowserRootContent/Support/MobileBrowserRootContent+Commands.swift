import Foundation

extension MobileBrowserRootContent {
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
