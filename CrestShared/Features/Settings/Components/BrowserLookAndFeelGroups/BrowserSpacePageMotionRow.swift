import SwiftUI

/// The Window group's "Animate pages when switching Spaces" row, which every
/// platform offers. Off, a window's pages fade from one Space to the next
/// instead of sliding.
struct BrowserSpacePageMotionRow: View {
    let motion: CrestSettingValue<Bool>

    var body: some View {
        CrestSettingRow(
            "Animate pages when switching Spaces",
            setting: motion.resettable("Animate pages when switching Spaces")
        ) {
            Toggle("Animate pages when switching Spaces", isOn: motion.binding)
                .labelsHidden()
                .accessibilityIdentifier("animate-space-pages")
        }
        .browserAppearanceSetting(.spacePageMotion)
    }
}

#if DEBUG
    #Preview("Animate pages when switching Spaces") {
        @Previewable @State var animatesSpacePages = SpacePageMotionPreference.defaultValue
        BrowserSpacePageMotionRow(
            motion: CrestSettingValue($animatesSpacePages, default: SpacePageMotionPreference.defaultValue)
        )
        .padding()
        .frame(width: 520)
    }
#endif
