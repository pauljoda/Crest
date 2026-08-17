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
            setPermissionDecision: { permission, decision in
                Task {
                    await model.setPermissionDecision(
                        decision,
                        for: permission,
                        extensionSummary: summary
                    )
                }
            },
            setHostDecision: { hostPattern, decision in
                Task {
                    await model.setHostDecision(
                        decision,
                        for: hostPattern,
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
