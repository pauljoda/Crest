import SwiftUI

struct MobileCompactBrowserSurface<Sidebar: View, Page: View>: View {
    let compactShowsPage: Bool
    @Binding var isPagePresented: Bool
    let sidebar: Sidebar
    let page: Page

    var body: some View {
        sidebar
            .allowsHitTesting(!compactShowsPage)
            .accessibilityHidden(compactShowsPage)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .fullScreenCover(isPresented: $isPagePresented) {
                page
            }
    }
}
