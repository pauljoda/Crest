import SwiftUI

/// The same title and favicon in the list and in the travelling component.
/// Keeping the native Label layout also preserves its baseline and icon gap.
struct BrowserSidebarTabLabel: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let metrics: BrowserSidebarTabRowMetrics
    var leadingInset: CGFloat = 0
    var restoreSavedLocation: (() -> Void)?
    var titleOpacity = 1.0
    var iconOffset: CGFloat = 0

    var body: some View {
        Label {
            Text(tab.displayTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .browserTabResidency(isLoaded: isLoaded)
                .opacity(titleOpacity)
        } icon: {
            HStack(spacing: 3) {
                BrowserSidebarTabFavicon(
                    tab: tab, profileID: profileID, metrics: metrics,
                    isProminent: isSelected, isLoaded: isLoaded)
                if tab.placement == .saved, tab.isAwayFromSavedLocation, let restoreSavedLocation {
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
