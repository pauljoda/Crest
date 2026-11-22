import SwiftUI
import UIKit

/// Touch's Reset All: the shared choices, plus Space page motion and the Home
/// Screen icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue

    var body: some View {
        BrowserLookAndFeelResetFooter {
            animatesSpacePages = SpacePageMotionPreference.defaultValue
            guard UIApplication.shared.alternateIconName != nil else { return }
            Task { @MainActor in
                guard (try? await UIApplication.shared.setAlternateIconName(nil)) != nil else { return }
                NotificationCenter.default.post(name: BrowserPlatformCurrentAppIcon.didChange, object: nil)
            }
        }
    }
}
