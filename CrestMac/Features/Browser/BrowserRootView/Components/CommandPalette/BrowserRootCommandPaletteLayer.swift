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
            isSourceAvailable
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
                morphID: BrowserRootCommandSurfaceID.address(
                    spaceID: model.browser.selectedSpace?.id
                ),
                overlayContentInsets: contentInsets,
                emptySelectionActions: emptySelectionActions
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

    private var isSourceAvailable: Bool {
        if let source = model.selectedTabAssignment {
            return model.isPaletteSourceAvailable(source)
        }
        return emptySelectionActions?.isAvailable == true
    }

    private var emptySelectionActions: BrowserEmptySelectionPaletteActions? {
        guard let space = model.browser.selectedSpace, model.browser.selectedTab == nil else { return nil }
        return BrowserEmptySelectionPaletteActions(
            source: BrowserSpaceRuntimeAssignment(space: space),
            browser: model.browser,
            accessController: model.spaceAccess,
            didSelectTab: {
                model.pages.select(session: model.browser.session)
                model.address = model.browser.selectedTab?.url?.absoluteString ?? ""
            }
        )
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
            extensionSidebar: model.extensionSidebar
        )
    }
}
