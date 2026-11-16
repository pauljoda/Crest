import SwiftUI
import UIKit

/// Touch's Reset All: the shared choices, plus the Home Screen icon.
struct BrowserPlatformLookAndFeelResetSection: View {
    var body: some View {
        BrowserLookAndFeelResetFooter {
            guard UIApplication.shared.alternateIconName != nil else { return }
            Task { @MainActor in
                guard (try? await UIApplication.shared.setAlternateIconName(nil)) != nil else { return }
                NotificationCenter.default.post(name: BrowserPlatformCurrentAppIcon.didChange, object: nil)
            }
        }
    }
}
