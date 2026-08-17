import SwiftUI

struct BrowserQuickWindowSettingsSection: View {
    @Binding var archivePolicy: BrowserQuickWindowArchivePolicy
    @Binding var remembersSpaceBySite: Bool

    var body: some View {
        Section("Quick Window") {
            Picker("Auto-archive", selection: $archivePolicy) {
                ForEach(BrowserQuickWindowArchivePolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }

            Toggle(
                "Remember the chosen Space for each site",
                isOn: $remembersSpaceBySite
            )

            BrowserPlatformLinkSettingsGuidance(kind: .quickWindow)
        }
    }
}
