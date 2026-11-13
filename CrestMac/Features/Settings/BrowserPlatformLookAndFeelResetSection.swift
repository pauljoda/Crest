import SwiftUI

/// The desktop's Reset All: the shared choices, plus Space page motion and the
/// Dock icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarFullscreenRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue
    @AppStorage(SidebarSpaceShortcutRevealPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var revealsSidebarOnSpaceShortcut = SidebarSpaceShortcutRevealPreference.defaultValue

    var body: some View {
        BrowserLookAndFeelResetFooter {
            animatesSpacePages = SpacePageMotionPreference.defaultValue
            BrowserDeviceAppearanceStore.shared.sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
            revealsSidebarInFullscreen = SidebarFullscreenRevealPreference.defaultValue
            revealsSidebarOnSpaceShortcut = SidebarSpaceShortcutRevealPreference.defaultValue
            _ = BrowserMacDockTile.shared.select("")
        }
    }
}
