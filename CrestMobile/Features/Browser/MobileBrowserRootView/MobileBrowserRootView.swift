import SwiftUI

struct MobileBrowserRootView: View {
    private let dataDeleter: any BrowserSpaceDataDeleting
    private let transientBrowsing: BrowserTransientBrowsingCoordinator
    private let suspendsCompactPagePresentation: Bool
    private let togglePrivateBrowsing: () -> Void
    private let closePrivateBrowsing: () -> Void

    @State private var model: MobileBrowserRootModel

    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        dataDeleter: any BrowserSpaceDataDeleting,
        navigation: MobileBrowserNavigationState,
        transientBrowsing: BrowserTransientBrowsingCoordinator,
        spaceAccess: BrowserSpaceAccessController = BrowserSpaceAccessController(),
        windowState: BrowserWindowStateStore? = nil,
        suspendsCompactPagePresentation: Bool = false,
        startupBehavior: BrowserStartupBehavior = .waitForTabSelection,
        togglePrivateBrowsing: @escaping () -> Void,
        closePrivateBrowsing: @escaping () -> Void
    ) {
        self.dataDeleter = dataDeleter
        self.transientBrowsing = transientBrowsing
        self.suspendsCompactPagePresentation = suspendsCompactPagePresentation
        self.togglePrivateBrowsing = togglePrivateBrowsing
        self.closePrivateBrowsing = closePrivateBrowsing
        let fallbackWidth =
            windowState?.sidebarWidth.map { CGFloat($0) }
            ?? BrowserSidebarWidthPreference.value(
                forKey: MobileBrowserRootPreferences.regularSidebarWidthKey,
                default: MobileBrowserRootLayout.defaultRegularSidebarWidth
            )
        _model = State(
            initialValue: MobileBrowserRootModel(
                browser: browser,
                pages: pages,
                navigation: navigation,
                spaceAccess: spaceAccess,
                windowState: windowState,
                startupBehavior: startupBehavior,
                persistedSidebarWidth:
                    windowState?.sidebarWidth.map { CGFloat($0) }
                    ?? fallbackWidth
            )
        )
    }

    var body: some View {
        MobileBrowserRootContent(
            model: model,
            dataDeleter: dataDeleter,
            transientBrowsing: transientBrowsing,
            suspendsCompactPagePresentation: suspendsCompactPagePresentation,
            togglePrivateBrowsing: togglePrivateBrowsing,
            closePrivateBrowsing: closePrivateBrowsing
        )
    }
}

#Preview("Mobile Browser Root") {
    let fixture = MobileBrowserPreviewFixture()
    MobileBrowserRootView(
        browser: fixture.browser,
        pages: fixture.pages,
        dataDeleter: fixture.pages,
        navigation: MobileBrowserNavigationState(),
        transientBrowsing: BrowserTransientBrowsingCoordinator(),
        spaceAccess: fixture.spaceAccess,
        windowState: fixture.windowState,
        togglePrivateBrowsing: {},
        closePrivateBrowsing: {}
    )
}
