import SwiftUI

struct PinnedTabSelectionButton: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let siteTheme: BrowserTabIconAccent?
    let select: () -> Void
    var isMultiSelected = false
    var branding: BrowserSpaceBranding? = nil
    let iconCustomization: BrowserIconCustomizationPresentation

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @State private var isHovering = false
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var iconScale = 1.0

    var body: some View {
        Button(action: select) {
            icon
                .font(.system(size: 17 * BrowserSidebarDensityPolicy.scale(iconScale), weight: .medium))
                .browserTabResidency(isLoaded: tab.nativeContent != nil || isLoaded)
                .browserIconCustomizationPopover(iconCustomization, arrowEdge: iconPickerArrowEdge)
                .frame(maxWidth: .infinity)
                .frame(
                    height: BrowserSidebarDensityPolicy.pinHeight(scale: iconScale, touch: capabilities.supportsTouch)
                )
                .contentShape(.rect)
                .modifier(
                    PinnedTabInteractionSurface(
                        favicon: tab.iconMode.showsFavicon ? favicons.icon(of: tab.id) : nil,
                        siteTheme: siteTheme,
                        isSelected: isSelected,
                        isHovering: isHovering || isMultiSelected,
                        isMultiSelected: isMultiSelected,
                        branding: branding
                    )
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var icon: some View {
        TabStateFaviconView(
            tab: tab, favicons: favicons, profileID: profileID, size: 19 * BrowserSidebarDensityPolicy.scale(iconScale))
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
