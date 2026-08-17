import SwiftUI

struct BrowserMozillaAddonsInstallHeader: View {
    let phase: BrowserMozillaAddonsInstallPhase
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
                    provenanceTitle,
                    systemImage: "checkmark.seal.fill"
                )
                .font(.caption)
                .foregroundStyle(.green)
            }
            Spacer(minLength: CrestSpacing.medium)
        }
    }

    private var provenanceTitle: String {
        phase.candidate?.isMozillaRecommended == true
            ? "Mozilla-signed package, Recommended by Mozilla"
            : "Mozilla-signed Firefox Add-ons package"
    }
}
