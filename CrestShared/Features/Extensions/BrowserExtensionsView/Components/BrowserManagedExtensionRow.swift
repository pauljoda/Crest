import SwiftUI

struct BrowserManagedExtensionRow: View {
    let model: BrowserExtensionsModel
    let summary: BrowserExtensionSummary
    let platformActions: BrowserExtensionPlatformActions

    var body: some View {
        BrowserExtensionRow(
            summary: summary,
            spaceID: model.space.id,
            extensionControllerPool: model.extensionControllerPool,
            platformActions: platformActions,
            isBusy: model.operationExtensionID == summary.id,
            setEnabled: { enabled in
                Task {
                    await model.setEnabled(
                        enabled,
                        extensionSummary: summary
                    )
                }
            },
            requestRemoval: {
                model.requestRemoval(of: summary)
            }
        )
    }
}

#Preview("Managed Extension", traits: .fixedLayout(width: 560, height: 180)) {
    List {
        BrowserManagedExtensionRow(
            model: BrowserExtensionsPreviewFixture.model,
            summary: BrowserExtensionsPreviewFixture.summary,
            platformActions: .none
        )
    }
}
