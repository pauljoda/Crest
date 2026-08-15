import SwiftUI

@MainActor
enum MobileBrowserRootPreviewFixture {
    static func makeModel(
        fixture: MobileBrowserPreviewFixture
    ) -> MobileBrowserRootModel {
        MobileBrowserRootModel(
            browser: fixture.browser,
            pages: fixture.pages,
            navigation: MobileBrowserNavigationState(),
            spaceAccess: fixture.spaceAccess,
            windowState: fixture.windowState,
            startupBehavior: .waitForTabSelection,
            persistedSidebarWidth: MobileBrowserRootLayout.defaultRegularSidebarWidth
        )
    }
}
