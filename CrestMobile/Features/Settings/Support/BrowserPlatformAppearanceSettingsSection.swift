import SwiftUI

/// The shared Window group, plus Space page motion. Touch has no window
/// transparency of its own to add to it.
struct BrowserPlatformAppearanceSettingsSection: View {
    var space: BrowserSpaceAppearance?
    var showsPreview = false

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue

    var body: some View {
        let motion = CrestSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)
        BrowserWindowAppearanceGroup(
            space: space,
            showsPreview: showsPreview,
            extraSettings: [(.spacePageMotion, motion.resettable("Animate pages when switching Spaces"))]
        ) {
            BrowserSpacePageMotionRow(motion: motion)
        }
    }
}
