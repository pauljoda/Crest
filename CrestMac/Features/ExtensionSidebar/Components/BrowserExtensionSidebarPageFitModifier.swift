import SwiftUI

/// Responsive pages reflow at their requested zoom. A page with a wider CSS
/// minimum temporarily fits the card while an extension panel occupies the row.
struct BrowserExtensionSidebarPageFitModifier: ViewModifier {
    let page: BrowserPage?
    let isEnabled: Bool
    @State private var owner = UUID()
    @State private var width: CGFloat = 0
    @State private var fittedPage: BrowserPage?

    private struct Request: Equatable {
        var page: ObjectIdentifier?
        var enabled: Bool
        var width: CGFloat
        var zoom: CGFloat
        var navigation: Int
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .task(
                id: Request(
                    page: page.map(ObjectIdentifier.init), enabled: isEnabled, width: width,
                    zoom: page?.pageZoom ?? 1, navigation: page?.completedNavigationCount ?? 0)
            ) {
                if fittedPage !== page {
                    fittedPage?.releaseViewportFit(owner: owner)
                    fittedPage = page
                }
                guard let page else { return }
                if isEnabled {
                    await page.fitViewport(width: width, owner: owner)
                } else {
                    page.releaseViewportFit(owner: owner)
                }
            }
            .onDisappear {
                fittedPage?.releaseViewportFit(owner: owner)
                fittedPage = nil
            }
    }
}
