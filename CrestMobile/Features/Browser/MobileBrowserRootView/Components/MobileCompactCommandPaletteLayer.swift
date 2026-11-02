import SwiftUI

/// A compact window's command palette, grown out of its address bar at the
/// bottom of the screen: the address stays the input line and the results
/// rise above the bar, the best match nearest it.
struct MobileCompactCommandPaletteLayer: View {
    // MARK: - Types

    /// Where the compact address bar lies, which the palette grows out of.
    struct FieldAnchor: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil

        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = value ?? nextValue()
        }
    }

    // MARK: - Variables

    @Binding var mode: BrowserCommandPaletteMode?
    let browser: BrowserStore
    let commands: BrowserCommandPaletteCommandRegistry?
    let isSourceAvailable: (BrowserTabRuntimeAssignment) -> Bool
    let selectTab: (BrowserTabRuntimeAssignment, BrowserTabRuntimeAssignment) -> Bool
    let openURL: (BrowserTabRuntimeAssignment, URL) -> Bool
    let fieldFrame: CGRect?

    @ViewBuilder
    var body: some View {
        if let mode, let fieldFrame, let source = browser.shownTabAssignment, isSourceAvailable(source) {
            BrowserCommandPalette(
                browser: browser,
                space: browser.shownSpace,
                selectedTabID: source.tabID,
                initialQuery: mode.initialQuery,
                commands: commands,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectTab,
                openURL: { source, url, _ in openURL(source, url) },
                dismiss: { self.mode = nil },
                presentation: .rising,
                fieldFrame: fieldFrame
            )
            .id(BrowserCommandPalettePresentationIdentity(mode: mode, space: browser.shownSpace, source: source))
            .transition(.browserCommandPaletteOverlay)
        }
    }
}
