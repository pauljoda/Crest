import SwiftUI

struct MobileSpaceSettingsButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MobileSpaceUtilityButtonLabel(systemImage: "gearshape")
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("space-settings-button")
    }
}

#Preview("Space Settings Button", traits: .sizeThatFitsLayout) {
    MobileSpaceSettingsButton(action: {})
        .buttonStyle(.plain)
        .padding()
}
