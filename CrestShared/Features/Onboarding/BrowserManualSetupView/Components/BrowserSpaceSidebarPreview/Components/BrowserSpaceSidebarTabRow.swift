import SwiftUI

struct BrowserSpaceSidebarTabRow: View {
    let tab: BrowserTab
    let profileID: UUID
    let isSelected: Bool

    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults)
    private var tabScale = 1.0

    var body: some View {
        BrowserSpaceSidebarTabRowContent(
            tab: tab, profileID: profileID, isSelected: isSelected,
            tabScale: tabScale, appearance: BrowserDeviceAppearanceStore.shared.tabs
        )
    }
}
