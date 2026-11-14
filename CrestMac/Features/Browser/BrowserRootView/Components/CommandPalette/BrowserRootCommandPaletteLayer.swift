import AppKit
import SwiftUI

struct BrowserRootCommandPaletteLayer: View {
    let model: BrowserRootModel
    let shortcuts: BrowserShortcutStore?
    var spaceSettingsPresentation: BrowserSpaceSettingsPresentationState? = nil
    let commandSurfaceNamespace: Namespace.ID
    var contentInsets = EdgeInsets()

    @Environment(\.browserMacWindows) private var windows
    @Environment(\.layoutDirection) private var layoutDirection

    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    var body: some View {
        if let mode = model.chrome.commandPaletteMode,
            model.isCommandPaletteShown
        {
            BrowserCommandPalette(
                browser: model.browser,
                space: paletteSpace,
                selectedTabID: model.browser.shownTab?.id,
                initialQuery: mode.initialQuery,
                commands: model.paletteRegistry(
                    windows: windows, layoutDirection: layoutDirection, shortcuts: shortcuts,
                    settings: spaceSettingsPresentation),
                isSourceAvailable: model.isPaletteSourceAvailable,
                selectTab: model.selectPaletteTab,
                openURL: { source, url, opening in
                    model.openPaletteURL(url, mode: mode, from: source, opening: opening, windows: windows)
                },
                dismiss: model.chrome.dismissCommandPalette,
                morphNamespace: commandSurfaceNamespace,
                overlayContentInsets: contentInsets,
                destination: model.emptySelectionPaletteActions,
                openings: BrowserCommandPaletteOpening.all,
                readPasteboard: { NSPasteboard.general.string(forType: .string) }
            )
            .id(
                BrowserCommandPalettePresentationIdentity(
                    mode: mode,
                    space: paletteSpace,
                    source: model.selectedTabAssignment
                )
            )
            // The same scheme as the address field it grows out of.
            .environment(\.colorScheme, paletteColorScheme)
            .transition(.browserCommandPaletteOverlay)
            .zIndex(BrowserRootMetrics.commandPaletteZIndex)
        }
    }

    /// The palette's scheme: the material color's, over the Space it searches.
    private var paletteColorScheme: ColorScheme {
        let spaceScheme = paletteSpace?.settings.look.shown.colorScheme(over: colorScheme) ?? colorScheme
        return CrestSurfaceTone.shownScheme(over: spaceScheme, window: colorScheme)
    }

    /// The Space the window shows, unless it is being deleted.
    private var paletteSpace: SpaceModel? {
        model.browser.shownSpace
    }
}
