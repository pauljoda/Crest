import SwiftUI

/// Supplies live appearance preferences at the scene boundary.
struct BrowserChromeAppearancePersistence: ViewModifier {
    @AppStorage(BrowserChromeAppearancePreference.sidebarOnRightKey, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarOnRight = false
    @AppStorage(BrowserChromeAppearancePreference.borderWidthKey, store: BrowserChromeAppearancePreference.defaults)
    private var borderWidth = BrowserChromeAppearance.defaultBorderWidth

    func body(content: Content) -> some View {
        content.environment(
            \.browserChromeAppearance,
            BrowserChromeAppearance(sidebarOnRight: sidebarOnRight, borderWidth: borderWidth)
        )
    }
}
