import SwiftUI

struct BrowserChromeWebStoreInstallHeader: View {
    let phase: BrowserChromeWebStoreInstallPhase
    let spaceID: SpaceID

    var body: some View {
        BrowserExtensionInstallHeader(
            title: phase.headerTitle,
            extensionID: phase.candidate?.id,
            spaceID: spaceID,
            iconPayload: phase.candidate?.iconPayload
        ) {
            Label(
                "Verified Chrome Web Store package",
                systemImage: "checkmark.seal.fill"
            )
            .foregroundStyle(.green)
        }
    }
}
