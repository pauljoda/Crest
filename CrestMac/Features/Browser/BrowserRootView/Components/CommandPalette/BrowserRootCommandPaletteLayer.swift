import SwiftUI

struct BrowserRootCommandPaletteLayer: View {
    let model: BrowserRootModel
    let shortcuts: BrowserShortcutStore?
    let commandSurfaceNamespace: Namespace.ID

    @Environment(\.openWindow) private var openWindow
    @Environment(\.layoutDirection) private var layoutDirection

    @ViewBuilder
    var body: some View {
        if let mode = model.chrome.commandPaletteMode,
            let source = model.paletteSourceAssignment,
            model.isPaletteSourceAvailable(source)
        {
            let otherSpaces = model.paletteOtherSpaces
            BrowserCommandPalette(
                space: model.browser.selectedSpace,
                selectedTabID: model.browser.selectedTab?.id,
                initialQuery: mode.initialQuery,
                otherSpaces: otherSpaces,
                commands: commandActions.paletteRegistry(shortcuts: shortcuts),
                isPrivateBrowsing: model.browser.isPrivateBrowsing,
                isSourceAvailable: model.isPaletteSourceAvailable,
                selectTab: model.selectPaletteTab,
                selectTabInSpace: model.selectPaletteTab,
                openURL: { source, url in
                    model.openPaletteURL(url, mode: mode, from: source)
                },
                dismiss: model.chrome.dismissCommandPalette,
                morphNamespace: commandSurfaceNamespace,
                morphID: BrowserRootCommandSurfaceID.address(
                    spaceID: model.browser.selectedSpace?.id
                )
            )
            .id(
                BrowserCommandPalettePresentationIdentity(
                    mode: mode,
                    space: model.browser.selectedSpace,
                    source: source,
                    otherSpaces: otherSpaces
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
            targetWindowID: nil,
            layoutDirection: layoutDirection
        )
    }
}
