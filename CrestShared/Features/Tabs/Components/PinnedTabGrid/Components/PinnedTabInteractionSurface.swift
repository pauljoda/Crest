import SwiftUI

struct PinnedTabInteractionSurface: ViewModifier {
    let faviconData: Data?
    let siteTheme: BrowserTabIconAccent?
    let isSelected: Bool
    let isHovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: BrowserFaviconPalette?

    func body(content: Content) -> some View {
        content
            .crestInteractiveSurface(
                isSelected: isSelected,
                isHovering: isHovering,
                cornerRadius: CrestRadius.compact,
                showsRestingSurface: true,
                selectedBorderColor: accent.color,
                selectedBorderWidth: CrestLayout.pinnedAccentBorderWidth
            )
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.palette,
                    reduceMotion: reduceMotion
                ),
                value: palette
            )
            .task(id: faviconData) {
                guard let faviconData else {
                    palette = nil
                    return
                }
                palette = await BrowserFaviconPaletteLoader.shared.palette(
                    for: faviconData
                )
            }
    }

    private var accent: BrowserTabIconAccent {
        BrowserTabIconAccentResolver.resolve(
            siteTheme: siteTheme,
            extracted: palette?.primary.iconAccent
        )
    }
}
