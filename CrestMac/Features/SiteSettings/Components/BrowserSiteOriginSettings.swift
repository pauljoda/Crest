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
            #if CREST_CHROMIUM_HOST
            if let native = page.chromiumPage {
                ChromiumSitePermissions(page: native)
            }
            #else
            BrowserSitePermissionDisclosure(
                origin: origin,
                spaceID: page.spaceID,
                permissionCenter: permissionCenter,
                didChange: { permission in
                    switch permission {
                    case .notifications:
                        page.synchronizeHostedWebNotificationPermission()
                    case .location:
                        page.synchronizeGeolocationPermission()
                    case .popups:
                        page.synchronizePopupPermission()
                    default:
                        break
                    }
                },
                isExpanded: $isExpanded
            )
            #endif
        }
    }
}

#if CREST_CHROMIUM_HOST
private struct ChromiumSitePermissions: View {
    let page: ChromiumNativePage
    @State private var permissions: [ChromiumNativePage.SitePermission] = []
    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.small) {
            Text("Permissions").font(.headline)
            ForEach(permissions) { permission in
                Picker(permission.label, selection: Binding(
                    get: { permissions.first { $0.id == permission.id }?.value ?? permission.value },
                    set: { value in
                        if page.setPermission(permission.id, value: value) { permissions = page.permissions }
                    })) {
                    if permission.supportsAsk { Text("Ask").tag(3) }
                    Text("Allow").tag(1)
                    Text("Block").tag(2)
                }
                .pickerStyle(.menu)
            }
        }
        .onAppear { permissions = page.permissions }
    }
}
#endif
