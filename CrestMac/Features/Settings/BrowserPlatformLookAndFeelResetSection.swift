import SwiftUI

/// The desktop's Reset All: the shared choices, plus Space page motion, the
/// sidebar's hover area, hover delay and slide time, and the Dock icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue

    var body: some View {
        BrowserLookAndFeelResetFooter {
            animatesSpacePages = SpacePageMotionPreference.defaultValue
            BrowserDeviceAppearanceStore.shared.sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
            BrowserDeviceAppearanceStore.shared.sidebarRevealDelay = SidebarRevealDelayPreference.defaultValue
            BrowserDeviceAppearanceStore.shared.sidebarSlideDuration = BrowserSidebarSlide.defaultValue
            revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue
            _ = BrowserMacDockTile.shared.select("")
        }
    }
}
