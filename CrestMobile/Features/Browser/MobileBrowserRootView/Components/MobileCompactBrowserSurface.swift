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

#Preview("Mobile Compact Browser Surface") {
    @Previewable @State var isPagePresented = false
    MobileCompactBrowserSurface(
        compactShowsPage: false,
        isPagePresented: $isPagePresented,
        sidebar: Color.indigo.opacity(0.1),
        page: ContentUnavailableView("Preview Page", systemImage: "globe")
    )
}
