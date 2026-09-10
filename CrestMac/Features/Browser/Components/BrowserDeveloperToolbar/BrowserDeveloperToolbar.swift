import SwiftUI

struct BrowserDeveloperToolbar: View {
    let page: BrowserPage
    let browser: BrowserStore
    let pages: BrowserPagePool
    let permissionCenter: BrowserSitePermissionCenter

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var address = ""
    @State private var showsSiteSettings = false
    @State private var showsCaptureOptions = false
    @State private var isSiteSettingsPermissionsExpanded =
        BrowserSitePermissionDisclosurePolicy.defaultIsExpanded

    var body: some View {
        BrowserPageToolbarSurface(label: "Developer Toolbar", identifier: "developer-toolbar") {
            controls
        } background: {
            BrowserDeveloperToolbarBackground(isOpaque: reduceTransparency)
        }
        .onAppear(perform: synchronizeAddress)
        .onChange(of: page.displayURL) { _, _ in synchronizeAddress() }
    }

    private var controls: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
            BrowserDeveloperViewportMenu(page: page)
            BrowserDeveloperToolbarDivider()
            BrowserDeveloperSiteSettingsControl(
                page: page,
                permissionCenter: permissionCenter,
                isPresented: $showsSiteSettings,
                permissionsExpansion: $isSiteSettingsPermissionsExpanded
            )
            BrowserDeveloperAddressField(
                address: $address,
                navigate: navigate
            )
            BrowserDeveloperToolbarButton(
                label: "Copy Link",
                systemImage: "link",
                action: page.copyDeveloperPageLink
            )
            BrowserDeveloperToolbarDivider()
            BrowserDeveloperCaptureControls(
                page: page,
                showsCaptureOptions: $showsCaptureOptions
            )
            BrowserDeveloperToolbarDivider()
            BrowserDeveloperInspectorControls(page: page)
        }
    }

    private func synchronizeAddress() {
        address = page.displayURL?.absoluteString ?? ""
    }

    private func navigate() {
        guard
            let url = AddressResolver.resolve(
                address,
                searchProvider: browser.selectedSpace?.browsingPreferences
                    .searchProvider ?? .google
            )
        else { return }
        if BrowserDeveloperNavigationPolicy.updatesSelectedTab(
            isActivePage: pages.activePage === page
        ) {
            browser.navigateSelectedTab(to: url)
            pages.load(url)
        } else {
            page.load(url)
        }
        address = url.absoluteString
    }
}
