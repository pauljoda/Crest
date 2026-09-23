import SwiftUI

struct BrowserSitePermissionDisclosure: View {
    let origin: BrowserSiteOrigin
    let spaceID: SpaceID
    let permissionCenter: BrowserSitePermissionCenter
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: CrestSpacing.small) {
                    Text("Permissions")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: CrestSpacing.small)
                    Image(
                        systemName: isExpanded
                            ? "chevron.down"
                            : "chevron.right"
                    )
                    .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Permissions")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            ForEach(
                BrowserSitePermissionDisclosurePolicy.visiblePermissions(
                    isExpanded: isExpanded
                ),
                id: \.self
            ) { permission in
                BrowserSitePermissionRow(
                    permission: permission,
                    origin: origin,
                    spaceID: spaceID,
                    permissionCenter: permissionCenter
                )
            }
        }
    }
}
