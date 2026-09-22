#if CREST_CHROMIUM_HOST
import SwiftUI

// The Chromium composition of the engine-contributed site sections. The names
// and signatures match the WebKit file in CrestMac; only one of the two is ever
// compiled into a target, so the shared presentation layer composes these
// without naming an engine or asking a compile-time condition of its own.

/// The engine keeps its own content settings, so the list comes from the page
/// rather than from Crest's permission centre.
struct BrowserEngineSitePermissionsSection: View {
    let page: BrowserPage
    let origin: BrowserSiteOrigin
    let permissionCenter: BrowserSitePermissionCenter
    @Binding var isExpanded: Bool

    @State private var permissions: [ChromiumNativePage.SitePermission] = []

    var body: some View {
        if let native = page.chromiumPage {
            VStack(alignment: .leading, spacing: CrestSpacing.small) {
                Text("Permissions").font(.headline)
                ForEach(permissions) { permission in
                    Picker(
                        permission.label,
                        selection: Binding(
                            get: {
                                permissions.first { $0.id == permission.id }?.value
                                    ?? permission.value
                            },
                            set: { value in
                                if native.setPermission(permission.id, value: value) {
                                    permissions = native.permissions
                                }
                            })
                    ) {
                        if permission.supportsAsk { Text("Ask").tag(3) }
                        Text("Allow").tag(1)
                        Text("Block").tag(2)
                    }
                    .pickerStyle(.menu)
                }
            }
            .onAppear { permissions = native.permissions }
        }
    }
}

/// Per-site extension actions and access, alongside Crest's own site controls.
struct BrowserEngineSiteControlsSection: View {
    let page: BrowserPage
    let space: BrowserSpace
    let url: URL?
    let dismiss: () -> Void

    var body: some View {
        if let native = page.chromiumPage {
            ChromiumExtensionControls(
                page: native, space: space, url: url, dismiss: dismiss)
        }
    }
}

/// The pinned extension actions that sit above a Space's tab list.
struct BrowserEngineSidebarAccessory: View {
    let space: BrowserSpace
    /// The window's own store. Extension ownership is decided against the store
    /// family that owns this window rather than against one global Space list.
    let browser: BrowserStore
    let pages: BrowserPagePool

    var body: some View {
        BrowserPinnedExtensionStrip(
            page: pinnedActionPage, space: space, browser: browser)
    }

    private var pinnedActionPage: ChromiumNativePage? {
        guard let tabID = space.selectedTabID else { return nil }
        return pages.activePage(
            matching: BrowserTabRuntimeAssignment(
                tabID: tabID, spaceID: space.id, profileID: space.profile.id)
        )?.chromiumPage
    }
}

/// The Extensions settings destination, composed by the engine that has them.
struct BrowserEngineExtensionSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var requestedSpaceID: SpaceID?
    var requestRevision = 0

    var body: some View {
        BrowserExtensionSettingsPane(
            browser: browser, spaceAccess: spaceAccess,
            requestedSpaceID: requestedSpaceID, requestRevision: requestRevision)
    }
}
#endif
