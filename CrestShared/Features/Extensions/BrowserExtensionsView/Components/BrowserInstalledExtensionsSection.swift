import SwiftUI

struct BrowserInstalledExtensionsSection: View {
    let model: BrowserExtensionsModel
    let platformActions: BrowserExtensionPlatformActions

    var body: some View {
        Section("Installed in this Space") {
            SpaceExtensionScopeBanner(space: model.space)

            if model.extensions.isEmpty {
                BrowserExtensionEmptyState()
            } else {
                ForEach(model.extensions) { extensionSummary in
                    BrowserManagedExtensionRow(
                        model: model,
                        summary: extensionSummary,
                        platformActions: platformActions
                    )
                }
            }
        }
    }
}

#Preview("Installed Extensions") {
    Form {
        BrowserInstalledExtensionsSection(
            model: BrowserExtensionsPreviewFixture.model,
            platformActions: .none
        )
    }
    .frame(width: 560, height: 260)
}
