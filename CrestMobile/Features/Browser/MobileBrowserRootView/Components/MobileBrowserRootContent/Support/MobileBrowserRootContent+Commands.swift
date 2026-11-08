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
}
