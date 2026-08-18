import SwiftUI

struct MobileBrowserSidebarLayout: View {
    let configuration: MobileBrowserSidebarContentConfiguration

    var body: some View {
        MobileBrowserSidebarBottomChromeLayout(configuration: configuration) {
            if BrowserSidebarAccessPolicy.availableSpaces(
                in: configuration.browser
            ).isEmpty {
                ContentUnavailableView("No Spaces", systemImage: "square.grid.2x2")
            } else {
                MobileBrowserSidebarPager(configuration: configuration)
            }
        }
    }
}
