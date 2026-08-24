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
            if let notice = configuration.page.blockedPopupState.notice {
                BrowserBlockedPopupSiteControlNotice(
                    notice: notice,
                    allow: {
                        configuration.page.allowAutomaticPopupsForBlockedSite()
                        permissionsExpansion = true
                    }
                )
            }
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
