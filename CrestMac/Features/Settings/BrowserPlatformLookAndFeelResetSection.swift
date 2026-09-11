import SwiftUI

/// The desktop's Reset All: the shared choices, plus window transparency, Space
/// page motion, and the Dock icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    @Environment(BrowserWindowTransparencyStore.self) private var transparency

    var body: some View {
        BrowserLookAndFeelResetFooter {
            transparency.isEnabled = BrowserWindowTransparencyPolicy.defaultEnabled
            transparency.strength = BrowserWindowTransparencyPolicy.defaultStrength
            animatesSpacePages = SpacePageMotionPreference.defaultValue
            _ = BrowserMacAppIconPreference.select("")
        }
    }
}
