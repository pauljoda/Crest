import SwiftUI

struct BrowserSavedSitePermissionSection: View {
    let records: [BrowserSitePermissionRecord]
    let permissionCenter: BrowserSitePermissionCenter
    let resetAll: () -> Void

    var body: some View {
        Section("Saved decisions") {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Saved Permissions",
                    systemImage: "hand.raised.slash",
                    description: Text(
                        "Sites will ask before using protected capabilities, opening pop-ups, or starting automatic downloads in this Space."
                    )
                )
                .frame(maxWidth: .infinity)
            } else {
                ForEach(records) { record in
                    BrowserSitePermissionRecordRow(
                        record: record,
                        permissionCenter: permissionCenter
                    )
                }
            }

            Button("Reset All", role: .destructive, action: resetAll)
                .buttonStyle(.crestDestructive)
                .disabled(records.isEmpty)
                .accessibilityHint("Makes every site ask again in this Space")
        }
    }
}

#Preview("Saved Site Permissions") {
    Form {
        BrowserSavedSitePermissionSection(
            records: [BrowserPrivacySettingsPreviewFixture.record],
            permissionCenter:
                BrowserPrivacySettingsPreviewFixture.permissionCenter,
            resetAll: {}
        )
    }
}
