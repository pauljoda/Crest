import SwiftUI

struct BrowserSettingsPrivateSpaceAccessRow: View {
    let space: BrowserSpace
    let accessController: BrowserSpaceAccessController

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            BrowserSettingsPrivateSpaceIdentity(space: space)
            Spacer(minLength: CrestSpacing.small)
            BrowserSettingsPrivateSpaceUnlockControl(
                space: space,
                accessController: accessController
            )
        }
        .frame(minHeight: CrestFormRowMetrics.minimumHeight)
        .accessibilityElement(children: .contain)
    }
}

#Preview("Private Space row") {
    Form {
        BrowserSettingsPrivateSpaceAccessRow(
            space: BrowserSettingsPrivateSpaceAccessPreviewFixture.space,
            accessController: BrowserSettingsPrivateSpaceAccessPreviewFixture.accessController
        )
    }
    .frame(maxWidth: 520)
}
