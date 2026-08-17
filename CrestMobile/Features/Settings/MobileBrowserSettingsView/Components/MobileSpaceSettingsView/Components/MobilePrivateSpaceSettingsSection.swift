import SwiftUI

struct MobilePrivateSpaceSettingsSection: View {
    @Binding var requiresAuthentication: Bool
    let isUpdating: Bool

    var body: some View {
        Section("Private Space") {
            Toggle(
                "Require device authentication",
                isOn: $requiresAuthentication
            )
            .disabled(isUpdating)
            .accessibilityIdentifier("private-space-toggle")

            if isUpdating {
                ProgressView("Updating Space protection…")
            }

            Text(
                "Crest uses Face ID, Touch ID, or the normal device passcode or password. Private Spaces lock again when Crest leaves the foreground."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}
