import SwiftUI

struct BrowserSiteControlContent: View {
    let configuration: BrowserSiteControlConfiguration
    let actions: [BrowserExtensionActionPresentation]
    @Binding var permissionsExpansion: Bool
    let dismiss: () -> Void
    let manageExtensions: () -> Void
    let performExtensionAction: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    let togglePinned: (BrowserExtensionActionPresentation) -> Void
    let reviewCertificate: () -> Void
    var presentExtensionMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserSiteControlHeader(page: configuration.page)
            BrowserSiteQuickActions(
                page: configuration.page,
                dismiss: dismiss
            )
            BrowserSiteExtensionsSection(
                actions: actions,
                manageExtensions: manageExtensions,
                perform: performExtensionAction,
                togglePinned: togglePinned,
                presentMenu: presentExtensionMenu
            )
            Divider()
            BrowserSiteSettingsContent(
                page: configuration.page,
                permissionCenter: configuration.permissionCenter,
                reviewCertificate: reviewCertificate,
                permissionsExpansion: $permissionsExpansion
            )
        }
        .padding(CrestSpacing.medium)
    }
}

#Preview("Site Control Content") {
    @Previewable @State var permissionsExpansion = true
    let preview = BrowserSidebarExtensionPreviewFixture.makeContext()
    BrowserSiteControlContent(
        configuration: preview.configuration,
        actions: BrowserSidebarExtensionPreviewFixture.actions,
        permissionsExpansion: $permissionsExpansion,
        dismiss: {},
        manageExtensions: {},
        performExtensionAction: { _, _ in },
        togglePinned: { _ in },
        reviewCertificate: {}
    )
    .frame(width: BrowserSiteControlLayoutPolicy.width)
}
