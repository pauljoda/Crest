import SwiftUI

/// The same title and favicon in the list and in the travelling component.
/// Keeping the native Label layout also preserves its baseline and icon gap.
struct BrowserSidebarTabLabelContent: View {
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let metrics: BrowserSidebarTabRowMetrics
    var leadingInset: CGFloat = 0
    var restoreSavedLocation: (() -> Void)?
    var faviconPrimaryClick: (() -> Void)?
    var titleOpacity = 1.0
    var iconOffset: CGFloat = 0
    @Environment(\.browserInteractionCapabilities) private var capabilities
    let textScale: Double

    var body: some View {
        Label {
            Text(tab.displayTitle)
                .modifier(BrowserSidebarDensityFont(scale: textScale, supportsTouch: capabilities.supportsTouch))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .browserTabResidency(isLoaded: isLoaded)
                .opacity(titleOpacity)
        } icon: {
            HStack(spacing: 3) {
                BrowserSidebarTabFaviconContent(
                    tab: tab, favicons: favicons, profileID: profileID, metrics: metrics,
                    isProminent: isSelected, isLoaded: isLoaded,
                    iconScale: textScale
                )
                #if os(macOS)
                    .simultaneousGesture(
                        TapGesture().onEnded { faviconPrimaryClick?() },
                        including: faviconPrimaryClick == nil ? .none : .all
                    )
                #endif
                if tab.placement == .saved, tab.isAwayFromSavedAddress, let restoreSavedLocation {
                    BrowserTabSavedLocationIndicator(restore: restoreSavedLocation)
                        .browserTabResidency(isLoaded: isLoaded)
                }
            }
            .offset(x: iconOffset)
        }
        .padding(.leading, leadingInset)
        .frame(maxWidth: .infinity, maxHeight: metrics.fillsRowHeight ? .infinity : nil, alignment: .leading)
        .contentShape(.rect)
    }
}
