import AppKit
import SwiftUI

struct BrowserRootCommandPaletteLayer: View {
    let model: BrowserRootModel
    let shortcuts: BrowserShortcutStore?
    var spaceSettingsPresentation: BrowserSpaceSettingsPresentationState? = nil
    let commandSurfaceNamespace: Namespace.ID
    var contentInsets = EdgeInsets()
    /// Where this layer begins in the window, so the field the palette drops
    /// out of, which the window's fields report in its coordinates, can be
    /// placed here.
    var fieldOrigin = CGPoint.zero

    @Environment(\.browserMacWindows) private var windows
    @Environment(\.layoutDirection) private var layoutDirection

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isShown = model.isCommandPaletteShown
        ZStack {
            if let mode = model.chrome.commandPaletteMode, isShown {
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
                    readPasteboard: BrowserPasteboardStringCache.currentString,
                    loadsInitialAnswerSynchronously: fieldFrame != nil
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
        .animation(
            BrowserCommandSurfaceMorph.commandPaletteAnimation(reduceMotion: reduceMotion),
            value: isShown
        )
    }

    /// The field the palette drops out of while the address bar is on top, in
    /// this layer's coordinates, or nil to centre it over the window. Read
    /// here rather than handed down, so the window's shell never depends on
    /// the shown tab.
    private var fieldFrame: CGRect? {
        model.paletteFieldFrame?.offsetBy(dx: -fieldOrigin.x, dy: -fieldOrigin.y)
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

/// Caches the pasteboard string by `changeCount` so opening the command
/// palette skips repeated `pboard` IPC when the clipboard has not changed.
@MainActor
enum BrowserPasteboardStringCache {
    private static var lastChangeCount = Int.min
    private static var lastString: String?

    static func currentString() -> String? {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        if count == lastChangeCount {
            return lastString
        }
        lastChangeCount = count
        lastString = pasteboard.string(forType: .string)
        return lastString
    }
}
