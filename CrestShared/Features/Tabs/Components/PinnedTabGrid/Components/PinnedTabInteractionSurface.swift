import SwiftUI

struct PinnedTabInteractionSurface: ViewModifier {
    let favicon: FaviconAssets.Image?
    let siteTheme: BrowserTabIconAccent?
    let isSelected: Bool
    let isHovering: Bool
    var isMultiSelected = false
    var branding: SpaceBranding? = nil
    /// Whether another page shares the tab, which the tile outlines in the
    /// Space's accent while it lasts.
    var isSharedAsTab = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: BrowserFaviconPalette?
    @Environment(\.sidebarSpacePresentation) private var presentation

    func body(content: Content) -> some View {
        content
            .modifier(
                BrowserTabAppearanceSurface(
                    appearance: appearance,
                    accent: resolvedAccent,
                    isPinned: true, isSelected: isSelected, isHovering: isHovering,
                    selectionEmphasis: isMultiSelected)
            )
            .overlay {
                if isSharedAsTab {
                    RoundedRectangle(
                        cornerRadius: BrowserDeviceAppearanceStore.shared.sidebarCornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(selectionAccent, lineWidth: CrestLayout.pinnedAccentBorderWidth)
                    .allowsHitTesting(false)
                }
            }
            .animation(
                BrowserVisualAccessibilityPolicy.animation(
                    CrestMotion.palette,
                    reduceMotion: reduceMotion
                ),
                value: resolvedAccent
            )
            .task(id: favicon?.identity) {
                guard let favicon else {
                    palette = nil
                    return
                }
                let extracted = await BrowserFaviconPaletteLoader.shared.palette(for: favicon.data)
                guard !Task.isCancelled else { return }
                palette = extracted
            }
    }

    private var accent: BrowserTabIconAccent? {
        BrowserTabIconAccentResolver.resolve(
            siteTheme: siteTheme,
            extracted: palette?.primary.iconAccent
        )
    }

    private var resolvedAccent: Color {
        appearance.usesWebsitePinColor ? (accent?.color ?? selectionAccent) : selectionAccent
    }

    private var selectionAccent: Color {
        (appearance.color ?? (presentation?.branding ?? branding)?.primaryColor ?? .indigo).color
    }

    private var appearance: BrowserTabAppearance { BrowserDeviceAppearanceStore.shared.tabs }
}
