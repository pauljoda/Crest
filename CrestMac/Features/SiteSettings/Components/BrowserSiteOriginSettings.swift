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
