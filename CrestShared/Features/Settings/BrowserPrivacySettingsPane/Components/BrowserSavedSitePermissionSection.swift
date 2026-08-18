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
                        "Protected capabilities ask first. Automatic pop-ups are blocked, and a site can download one file before asking to send more."
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
                .accessibilityHint("Restores each site's default permission behavior")
        }
    }
}
