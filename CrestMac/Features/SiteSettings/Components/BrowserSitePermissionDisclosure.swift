import SwiftUI

struct BrowserSitePermissionDisclosure: View {
    /// Whether the permissions list starts open where it first appears.
    nonisolated static let defaultIsExpanded = true

    let origin: SiteOrigin
    let spaceID: UUID
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
                    CrestFormDisclosureChevron(isExpanded: isExpanded)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Permissions")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            ForEach(isExpanded ? SitePermission.all.filter { $0.platforms.contains(.current) } : [], id: \.self) {
                permission in
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
