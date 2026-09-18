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
    var faviconPrimaryClick: (() -> Void)?
    var titleOpacity = 1.0
    var iconOffset: CGFloat = 0
    var sidePanelSpaceID: SpaceID?
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var textScale = 1.0

    var body: some View {
        BrowserSidebarTabLabelContent(
            tab: tab, profileID: profileID, isSelected: isSelected, isLoaded: isLoaded,
            metrics: metrics, leadingInset: leadingInset, restoreSavedLocation: restoreSavedLocation,
            faviconPrimaryClick: faviconPrimaryClick,
            titleOpacity: titleOpacity, iconOffset: iconOffset, sidePanelSpaceID: sidePanelSpaceID, textScale: textScale
        )
    }
}
