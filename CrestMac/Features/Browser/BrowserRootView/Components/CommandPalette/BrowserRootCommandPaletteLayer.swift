import AppKit
import SwiftUI

struct BrowserRootCommandPaletteLayer: View {
    let model: BrowserRootModel
    let shortcuts: BrowserShortcutStore?
    var spaceSettingsPresentation: BrowserSpaceSettingsPresentationState? = nil
    let commandSurfaceNamespace: Namespace.ID
    var contentInsets = EdgeInsets()
    /// The field the palette drops out of while the address bar is on top, in
    /// this layer's coordinates, or nil to centre it over the window.
    var fieldFrame: CGRect? = nil
    /// Whether that field is a split card's, which lives out of reach of this
    /// layer's namespace and needs a stand-in to grow the palette from.
    var fieldIsCard = false

    @Environment(\.browserMacWindows) private var windows
    @Environment(\.layoutDirection) private var layoutDirection

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                presentation: fieldFrame == nil ? .overlay : .dropping,
                morphNamespace: commandSurfaceNamespace,
                overlayContentInsets: contentInsets,
                fieldFrame: fieldFrame,
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
        } else if fieldIsCard, let fieldFrame, let paletteSpace,
            BrowserCommandSurfaceMorph.animatesCommandPalette(reduceMotion: reduceMotion)
        {
            fieldAnchor(fieldFrame, spaceID: paletteSpace.id)
        }
    }

    /// A split card's field frame, carrying the palette's identity while the
    /// palette is closed.
    ///
    /// The field itself lives in its card's own hosting view, out of reach of
    /// this layer's namespace, so a clear stand-in over the same frame holds
    /// the identity in its place, as the window's own field does. Removing it in
    /// the transaction that inserts the palette grows the palette out of the
    /// field, and putting it back as the palette leaves shrinks it in again.
    private func fieldAnchor(_ frame: CGRect, spaceID: UUID) -> some View {
        GeometryReader { proxy in
            let placement = BrowserChromeAppearance.placementFrame(
                for: frame, in: proxy.size.width, direction: layoutDirection)
            Color.clear
                .frame(width: frame.width, height: frame.height)
                .matchedGeometryEffect(
                    id: BrowserCommandSurfaceMorph.commandPalette(spaceID: spaceID),
                    in: commandSurfaceNamespace,
                    properties: .frame,
                    anchor: .center,
                    isSource: true
                )
                .position(x: placement.midX, y: placement.midY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
