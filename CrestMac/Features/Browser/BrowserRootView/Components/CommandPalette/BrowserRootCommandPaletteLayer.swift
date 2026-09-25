import SwiftUI

struct BrowserRootCommandPaletteLayer: View {
    let model: BrowserRootModel
    let shortcuts: BrowserShortcutStore?
    let commandSurfaceNamespace: Namespace.ID
    var contentInsets = EdgeInsets()

    @Environment(\.openWindow) private var openWindow
    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        if let mode = model.chrome.commandPaletteMode,
            model.isCommandPaletteShown
        {
            BrowserCommandPalette(
                space: model.browser.selectedSpace,
                selectedTabID: model.browser.selectedTab?.id,
                initialQuery: mode.initialQuery,
                commands: commandActions.paletteRegistry(shortcuts: shortcuts),
                isPrivateBrowsing: model.browser.isPrivateBrowsing,
                isSourceAvailable: model.isPaletteSourceAvailable,
                selectTab: model.selectPaletteTab,
                openURL: { source, url in
                    model.openPaletteURL(url, mode: mode, from: source)
                },
                dismiss: model.chrome.dismissCommandPalette,
                morphNamespace: commandSurfaceNamespace,
                overlayContentInsets: contentInsets,
                emptySelectionActions: model.emptySelectionPaletteActions
            )
            .id(
                BrowserCommandPalettePresentationIdentity(
                    mode: mode,
                    space: model.browser.selectedSpace,
                    source: model.selectedTabAssignment
                )
            )
            .transition(.browserCommandPaletteOverlay)
            .zIndex(BrowserRootMetrics.commandPaletteZIndex)
        }
    }

    private var commandActions: BrowserCommandActions {
        BrowserCommandActions(
            browser: model.browser,
            pages: model.pages,
            chrome: model.chrome,
            openWindow: openWindow,
            spaceAccess: model.spaceAccess,
            targetWindowID: model.windowState?.id,
            layoutDirection: layoutDirection,
        )
    }
}
