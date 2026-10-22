import SwiftUI

/// The desktop's Reset All: the shared choices, plus Space page motion and the
/// Dock icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @AppStorage(SidebarRevealWidthPreference.key, store: BrowserChromeAppearancePreference.defaults)
    private var sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
    @AppStorage(PictureInPictureMomentumPreference.key)
    private var pictureInPictureMomentumSpeed = PictureInPictureMomentumPreference.defaultValue.speed

    var body: some View {
        BrowserLookAndFeelResetFooter {
            animatesSpacePages = SpacePageMotionPreference.defaultValue
            sidebarRevealWidth = SidebarRevealWidthPreference.defaultValue
            pictureInPictureMomentumSpeed = PictureInPictureMomentumPreference.defaultValue.speed
            _ = BrowserMacDockTile.shared.select("")
        }
    }
}
