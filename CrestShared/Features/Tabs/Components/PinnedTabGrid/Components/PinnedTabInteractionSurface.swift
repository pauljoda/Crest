import SwiftUI

struct PinnedTabInteractionSurface: ViewModifier {
    // MARK: - Variables

    /// The colors the pin's favicon is seen in, once read from its image.
    let palette: BrowserFaviconPalette?
    let siteTheme: BrowserTabIconAccent?
    let isSelected: Bool
    let isHovering: Bool
    var isMultiSelected = false
    var branding: SpaceBranding? = nil
    /// The tab's page, whose statuses dress the tile while they last.
    var statusSource: BrowserTabStatusSource? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sidebarSpacePresentation) private var presentation

    // MARK: - Body

    func body(content: Content) -> some View {
        content
            .background {
                BrowserTabStatusSurfaces(
                    tab: statusSource,
                    style: BrowserTabStatusSurfaceStyle(
                        accent: selectionAccent, cornerRadius: BrowserSidebarMetrics.layerCornerRadius(),
                        barOpacity: CrestOpacity.prominentStatusSurface)
                )
            }
            .modifier(
                BrowserTabAppearanceSurface(
                    appearance: appearance,
                    accent: resolvedAccent,
                    isPinned: true, isSelected: isSelected, isHovering: isHovering,
                    selectionEmphasis: isMultiSelected)
            )
            .animation(
                CrestMotion.palette.unlessReducingMotion(reduceMotion),
                value: resolvedAccent
            )
    }

    // MARK: - Actions - Accent

    private var accent: BrowserTabIconAccent? {
        siteTheme?.preferring(extracted: palette?.primary.iconAccent) ?? palette?.primary.iconAccent
    }

    private var resolvedAccent: Color {
        appearance.usesWebsitePinColor ? (accent?.color ?? selectionAccent) : selectionAccent
    }

    private var selectionAccent: Color {
        (appearance.color ?? (presentation?.branding ?? branding)?.primaryColor ?? SpaceBranding.fallbackColor).color
    }

    private var appearance: BrowserTabAppearance { BrowserDeviceAppearanceStore.shared.tabs }
}
