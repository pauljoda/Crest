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
            ViewThatFits(in: .horizontal) {
                actionControls.fixedSize(horizontal: true, vertical: false)
                overflowMenu
            }
        }
    }

    private var actionControls: some View {
        HStack(spacing: BrowserDeveloperToolbarMetrics.itemSpacing) {
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

    private var overflowMenu: some View {
        Menu {
            Button("Copy Link", systemImage: "link", action: page.copyDeveloperPageLink)
            Menu("Capture Window", systemImage: "rectangle.inset.filled") {
                Button("Capture in Portrait Mode", systemImage: "rectangle.portrait.on.rectangle.portrait") {
                    page.savePortraitCapture()
                }
                Button("Copy Full Page Capture", systemImage: "doc.on.clipboard") {
                    page.copyFullPageCapture()
                }
            }
            Button("Capture", systemImage: "camera", action: page.beginRegionCapture)
            Divider()
            Button("Toggle Console", systemImage: "apple.terminal") { page.toggleDeveloperPanel(.console) }
            Button("Toggle Network Panel", systemImage: "network") { page.toggleDeveloperPanel(.network) }
            Button("Inspect Element", systemImage: "scope") { page.toggleDeveloperPanel(.elements) }
        } label: {
            Image(systemName: "ellipsis")
                .frame(
                    width: BrowserDeveloperToolbarMetrics.buttonSize, height: BrowserDeveloperToolbarMetrics.buttonSize)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Developer Tools")
        .accessibilityIdentifier("developer-tools-overflow")
        .help("Developer Tools")
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
