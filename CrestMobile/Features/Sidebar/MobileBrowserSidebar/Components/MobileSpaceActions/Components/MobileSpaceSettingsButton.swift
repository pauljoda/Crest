import SwiftUI

struct MobileSpaceSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MobileSpaceUtilityButtonLabel(title: "Settings", systemImage: "gearshape")
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier(BrowserMobileAccessibilityID.spaceSettingsButton)
    }
}

#if DEBUG
    #Preview("Component") {
        MobileSpaceSettingsButton(action: {}).padding()
    }
#endif
