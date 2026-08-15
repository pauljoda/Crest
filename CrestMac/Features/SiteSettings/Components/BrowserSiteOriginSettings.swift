import SwiftUI

struct BrowserSiteOriginSettings: View {
    let page: BrowserPage
    let origin: BrowserSiteOrigin
    var reviewCertificate: (() -> Void)?
    let permissionCenter: BrowserSitePermissionCenter
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            Divider()
            BrowserSiteSecuritySection(
                page: page,
                origin: origin,
                reviewCertificate: reviewCertificate
            )
            Divider()
            BrowserSitePermissionDisclosure(
                origin: origin,
                spaceID: page.spaceID,
                permissionCenter: permissionCenter,
                isExpanded: $isExpanded
            )
        }
    }
}

#Preview("Origin Settings") {
    @Previewable @State var isExpanded = true
    let preview = BrowserSiteSettingsPreviewFixture.makePage()
    BrowserSiteOriginSettings(
        page: preview.page,
        origin: BrowserSiteSettingsPreviewFixture.origin,
        permissionCenter: preview.permissionCenter,
        isExpanded: $isExpanded
    )
    .padding()
    .frame(width: 300)
}
