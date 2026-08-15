import SwiftUI

struct BrowserSettingsPrivateSpaceIdentity: View {
    let space: BrowserSpace

    var body: some View {
        Group {
            BrowserSpaceSymbolArtwork(space: space, size: 34, lockSize: 8)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(space.name)
                    .font(CrestTypography.controlTitle)
                Text("Private Space")
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
            }
        }
    }
}

#Preview("Private Space identity") {
    HStack {
        BrowserSettingsPrivateSpaceIdentity(
            space: BrowserSettingsPrivateSpaceAccessPreviewFixture.space
        )
    }
    .padding()
}
