import SwiftUI

struct BrowserMozillaAddonsInstallHeader: View {
    let phase: BrowserMozillaAddonsInstallPhase
    let spaceID: SpaceID

    var body: some View {
        BrowserExtensionInstallHeader(
            title: phase.headerTitle,
            extensionID: phase.candidate?.id,
            spaceID: spaceID,
            iconPayload: phase.candidate?.iconPayload
        ) {
            Label(
                provenanceTitle,
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
        }
    }

    private var provenanceTitle: String {
        phase.candidate?.isMozillaRecommended == true
            ? "Mozilla-signed package, Recommended by Mozilla"
            : "Mozilla-signed Firefox Add-ons package"
    }
}
