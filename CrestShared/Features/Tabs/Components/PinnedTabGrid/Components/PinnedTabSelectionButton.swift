import SwiftUI

struct PinnedTabSelectionButton: View {
    // MARK: - Variables

    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let siteTheme: BrowserTabIconAccent?
    let select: () -> Void
    var isMultiSelected = false
    var branding: SpaceBranding? = nil
    /// The tab's page, whose statuses dress the tile while they last.
    var statusSource: BrowserTabStatusSource? = nil
    let iconCustomization: BrowserIconCustomizationPresentation

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.tabFaviconIsReplaced) private var isIconReplaced
    @State private var isHovering = false
    /// The colors the pin's favicon is seen in, once read from its image.
    @State private var palette: BrowserFaviconPalette?
    private var iconScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }
    private var favicon: FaviconAssets.Image? { tab.iconMode.showsFavicon ? favicons.icon(of: tab.id) : nil }

    // MARK: - Body

    var body: some View {
        let contentScale = BrowserSidebarDensity(iconScale).contentScale
        let iconSize = 19 * contentScale
        let plateInset = CrestSpacing.extraSmall * contentScale
        Button(action: select) {
            icon
                .modifier(PinnedTabIconPlate(palette: palette, size: iconSize, inset: plateInset))
                .opacity(isIconReplaced ? 0 : 1)
                .font(.system(size: 17 * contentScale, weight: .medium))
                // The icon and its plate dim as one flattened layer. Dimming
                // animates here, and animating it on the live layers let the
                // icon flash back for a frame as the animation settled.
                .padding(plateInset)
                .drawingGroup()
                .padding(-plateInset)
                .browserTabResidency(isLoaded: tab.nativeContent != nil || isLoaded)
                .browserIconCustomizationPopover(iconCustomization, arrowEdge: iconPickerArrowEdge)
                .overlay(alignment: .bottomTrailing) {
                    TabEngineBadge(tabID: tab.id, scale: BrowserSidebarDensity(iconScale).contentScale)
                }
                .anchorPreference(key: TabFaviconBoundsKey.self, value: .bounds) { $0 }
                .frame(maxWidth: .infinity)
                .frame(
                    height: BrowserSidebarDensity(iconScale).pinHeight(touch: capabilities.supportsTouch)
                )
                .contentShape(.rect)
                .modifier(
                    PinnedTabInteractionSurface(
                        palette: palette,
                        siteTheme: siteTheme,
                        isSelected: isSelected,
                        isHovering: isHovering || isMultiSelected,
                        isMultiSelected: isMultiSelected,
                        branding: branding,
                        statusSource: statusSource
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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

    // MARK: - Actions - Icon

    private var icon: some View {
        TabStateFaviconView(
            tab: tab, favicons: favicons, profileID: profileID, size: 19 * BrowserSidebarDensity(iconScale).contentScale
        )
    }

    private var iconPickerArrowEdge: Edge? {
        #if os(macOS)
            .leading
        #else
            // Let the native popover fit around the pin on either sidebar side.
            // A forced leading arrow clips the picker beside a right-docked sidebar.
            nil
        #endif
    }
}
