import SwiftUI

struct PinnedTabInteractionSurface: ViewModifier {
    let faviconData: Data?
    let siteTheme: BrowserTabIconAccent?
    let isSelected: Bool
    let isHovering: Bool
    var isMultiSelected = false
    var branding: BrowserSpaceBranding? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: BrowserFaviconPalette?
    @Environment(\.sidebarSpacePresentation) private var presentation

    func body(content: Content) -> some View {
        content
            .modifier(
                BrowserTabAppearanceSurface(
                    appearance: appearance,
                    accent: appearance.usesWebsitePinColor
                        ? accent.color
                        : (appearance.color ?? (presentation?.branding ?? branding)?.primaryColor ?? .indigo).color,
                    isPinned: true, isSelected: isSelected, isHovering: isHovering,
                    selectionEmphasis: isMultiSelected)
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

    private var appearance: BrowserTabAppearance { BrowserDeviceAppearanceStore.shared.tabs }
}
