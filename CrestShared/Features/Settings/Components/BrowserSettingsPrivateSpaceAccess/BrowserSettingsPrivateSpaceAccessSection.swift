import SwiftUI

struct BrowserSettingsPrivateSpaceAccessSection: View {
    let space: BrowserSpace
    let accessController: BrowserSpaceAccessController
    var detail = "Unlock this Space to view or change its private settings."

    var body: some View {
        Section("Private Space") {
            Text(detail)
                .crestFormFootnote()

            BrowserSettingsPrivateSpaceAccessRow(
                space: space,
                accessController: accessController
            )
        }
        .accessibilityIdentifier("settings-private-space-lock")
    }
}

#Preview("Private Space access") {
    Form {
        BrowserSettingsPrivateSpaceAccessSection(
            space: BrowserSettingsPrivateSpaceAccessPreviewFixture.space,
            accessController: BrowserSettingsPrivateSpaceAccessPreviewFixture.accessController
        )
    }
    .frame(maxWidth: 520)
}
