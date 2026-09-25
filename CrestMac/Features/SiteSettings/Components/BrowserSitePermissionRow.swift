import SwiftUI

struct BrowserSitePermissionRow: View {
    let permission: SitePermission
    let origin: SiteOrigin
    let spaceID: SpaceID
    let permissionCenter: BrowserSitePermissionCenter

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Label(permission.title, systemImage: permission.symbol)
                .font(.caption)
            Spacer(minLength: CrestSpacing.small)
            Menu(permission.title(for: currentDecision)) {
                Group {
                    Button(permission.askChoiceTitle, systemImage: "questionmark.circle") {
                        setDecision(.ask)
                    }
                    Button("Allow", systemImage: "checkmark.circle") {
                        setDecision(.grantPersistently)
                    }
                    Button("Block", systemImage: "nosign") {
                        setDecision(.denyPersistently)
                    }
                }
                .crestMenuActionLabelStyle()
            }
            .menuStyle(.borderlessButton)
            .crestMenuActionLabelStyle()
            .fixedSize()
        }
    }

    private var currentDecision: SitePermissionDecision {
        permissionCenter.decision(
            for: permission,
            origin: origin,
            in: spaceID
        )
    }

    private func setDecision(_ decision: SitePermissionDecision) {
        permissionCenter.setDecision(
            decision,
            for: permission,
            origin: origin,
            in: spaceID
        )
    }
}
