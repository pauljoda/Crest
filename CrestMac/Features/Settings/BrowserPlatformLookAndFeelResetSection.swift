import SwiftUI

/// The desktop's Reset All: the shared choices, plus Space page motion and the
/// Dock icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarRevealWidthPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
    @AppStorage(SidebarEdgeRestHidePreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarEdgeRestHideDelay = SidebarEdgeRestHidePreference.defaultValue

    var body: some View {
        BrowserLookAndFeelResetFooter {
            animatesSpacePages = SpacePageMotionPreference.defaultValue
            sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
            sidebarEdgeRestHideDelay = SidebarEdgeRestHidePreference.defaultValue
            _ = BrowserMacDockTile.shared.select("")
        }
    }
}
