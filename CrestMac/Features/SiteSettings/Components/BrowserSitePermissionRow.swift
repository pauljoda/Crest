import SwiftUI

struct BrowserSitePermissionRow: View {
    let permission: BrowserSitePermission
    let origin: BrowserSiteOrigin
    let spaceID: SpaceID
    let permissionCenter: BrowserSitePermissionCenter
    var didChange: ((BrowserSitePermission) -> Void)?

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Label(permission.settingsLabel, systemImage: permission.symbol)
                .font(.caption)
            Spacer(minLength: CrestSpacing.small)
            Menu(currentDecision.settingsLabel) {
                Button("Ask") { setDecision(.ask) }
                Button("Allow") { setDecision(.grantPersistently) }
                Button("Block") { setDecision(.denyPersistently) }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var currentDecision: BrowserSitePermissionDecision {
        permissionCenter.decision(
            for: permission,
            origin: origin,
            in: spaceID
        )
    }

    private func setDecision(_ decision: BrowserSitePermissionDecision) {
        permissionCenter.setDecision(
            decision,
            for: permission,
            origin: origin,
            in: spaceID
        )
        didChange?(permission)
    }
}
