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
    var returnsToSavedAddress = false
    var savedTabAction: (() -> Void)? = nil
    var branding: SpaceBranding? = nil
    /// The tab's page, whose statuses dress the tile while they last.
    var statusSource: BrowserTabStatusSource? = nil
    let iconCustomization: BrowserIconCustomizationPresentation

    @Environment(\.browserInteractionCapabilities) private var capabilities
    @Environment(\.tabFaviconIsReplaced) private var isIconReplaced
    @State private var isHovering = false
    private var iconScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                icon
                    .opacity(isIconReplaced ? 0 : 1)
                    .font(.system(size: 17 * BrowserSidebarDensity(iconScale).scale, weight: .medium))
                    .browserTabResidency(isLoaded: tab.nativeContent != nil || isLoaded)
                    .browserIconCustomizationPopover(iconCustomization, arrowEdge: iconPickerArrowEdge)
                    .overlay(alignment: .bottomTrailing) {
                        TabEngineBadge(tabID: tab.id, scale: BrowserSidebarDensity(iconScale).scale)
                    }
                    .anchorPreference(key: TabFaviconBoundsKey.self, value: .bounds) { $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.shownTitle)
            if isSelected, let savedTabAction {
                Button(action: savedTabAction) {
                    Image(systemName: returnsToSavedAddress ? "arrow.uturn.backward" : "minus")
                        .font(
                            .system(
                                size: capabilities.trailingControlMetrics.glyphSize,
                                weight: capabilities.trailingControlMetrics.glyphWeight))
                }
                .buttonStyle(CrestChromeButtonStyle(controlSize: capabilities.trailingControlMetrics.controlSize))
                .disabled(!returnsToSavedAddress && !isLoaded)
                .accessibilityLabel(returnsToSavedAddress ? "Return to Saved URL" : "Put Tab to Sleep")
                .accessibilityIdentifier(returnsToSavedAddress ? "return-tab-to-saved-url" : "sleep-saved-tab")
                .help(returnsToSavedAddress ? "Return to Saved URL" : "Put Tab to Sleep")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: BrowserSidebarDensity(iconScale).pinHeight(touch: capabilities.supportsTouch))
        .contentShape(.rect)
        .modifier(
            PinnedTabInteractionSurface(
                favicon: tab.iconMode.showsFavicon ? favicons.icon(of: tab.id) : nil,
                siteTheme: siteTheme, isSelected: isSelected, isHovering: isHovering || isMultiSelected,
                isMultiSelected: isMultiSelected, branding: branding, statusSource: statusSource)
        )
        .onHover { isHovering = $0 }
    }

    private var icon: some View {
        TabStateFaviconView(
            tab: tab, favicons: favicons, profileID: profileID, size: 19 * BrowserSidebarDensity(iconScale).scale)
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
