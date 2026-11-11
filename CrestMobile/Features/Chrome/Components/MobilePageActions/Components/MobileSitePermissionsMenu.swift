import SwiftUI

/// The site's permissions for a page, each with Ask, Allow and Block, for the
/// page's Space. A page with no site to ask for shows nothing.
struct MobileSitePermissionsMenu: View {
    let page: MobileBrowserPage

    var body: some View {
        if let origin = page.live.documentURL.flatMap(SiteOrigin.init(url:)) {
            Menu("Site Permissions", systemImage: "slider.horizontal.3") {
                // A page on iOS cannot share the screen, so that choice is
                // not offered here.
                ForEach(SitePermission.all.filter { $0 != .screenSharing }, id: \.self) { permission in
                    Picker(
                        permission.title,
                        selection: Binding {
                            page.permissionCenter.decision(for: permission, origin: origin, in: page.spaceID)
                        } set: { decision in
                            page.permissionCenter.setDecision(
                                decision, for: permission, origin: origin, in: page.spaceID)
                        }
                    ) {
                        Text(permission.askChoiceTitle).tag(SitePermissionDecision.ask)
                        Text("Allow").tag(SitePermissionDecision.grantPersistently)
                        Text("Block").tag(SitePermissionDecision.denyPersistently)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }
}
