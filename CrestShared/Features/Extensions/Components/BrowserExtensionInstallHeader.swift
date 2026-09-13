import SwiftUI

struct BrowserExtensionInstallHeader<Provenance: View>: View {
    let title: String
    let extensionID: String?
    let spaceID: SpaceID
    let iconPayload: BrowserExtensionIconPayload?
    @ViewBuilder let provenance: () -> Provenance

    var body: some View {
        HStack(alignment: .center, spacing: CrestSpacing.medium) {
            BrowserExtensionIconView(
                extensionID: extensionID,
                spaceID: spaceID,
                payload: iconPayload,
                size: BrowserExtensionsMetrics.installReviewIconSize
            )
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text(title)
                    .font(.title3.weight(.semibold))
                provenance()
                    .font(.caption)
            }
            Spacer(minLength: CrestSpacing.medium)
        }
    }
}
