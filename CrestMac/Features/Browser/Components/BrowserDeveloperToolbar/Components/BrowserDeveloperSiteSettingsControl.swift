import SwiftUI

struct BrowserDeveloperSiteSettingsControl: View {
    let page: BrowserPage
    let permissionCenter: BrowserSitePermissionCenter
    @Binding var isPresented: Bool
    @Binding var permissionsExpansion: Bool

    var body: some View {
        BrowserDeveloperToolbarButton(
            label: "Site Settings",
            systemImage: "info.circle.fill",
            isActive: isPresented,
            action: { isPresented.toggle() }
        )
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            BrowserSiteSettingsContent(
                page: page,
                permissionCenter: permissionCenter,
                permissionsExpansion: $permissionsExpansion
            )
            .padding(14)
            .frame(width: 300)
        }
    }
}

#Preview("Developer Site Settings") {
    @Previewable @State var isPresented = true
    @Previewable @State var permissionsExpansion = true
    let preview = BrowserDetailPreviewFixture.makeWebContent()
    BrowserDeveloperSiteSettingsControl(
        page: preview.page,
        permissionCenter: BrowserSitePermissionCenter(),
        isPresented: $isPresented,
        permissionsExpansion: $permissionsExpansion
    )
    .padding()
}
