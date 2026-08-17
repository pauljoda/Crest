import SwiftUI

struct BrowserChromeWebStoreInstallHeader: View {
    let phase: BrowserChromeWebStoreInstallPhase
    let spaceID: SpaceID

    var body: some View {
        HStack(alignment: .center, spacing: CrestSpacing.medium) {
            BrowserExtensionIconView(
                extensionID: phase.candidate?.id,
                spaceID: spaceID,
                payload: phase.candidate?.iconPayload,
                size: BrowserExtensionsMetrics.installReviewIconSize
            )
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text(phase.headerTitle)
                    .font(.title3.weight(.semibold))
                Label(
                    "Verified Chrome Web Store package",
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
            Spacer(minLength: CrestSpacing.medium)
        }
    }
}
