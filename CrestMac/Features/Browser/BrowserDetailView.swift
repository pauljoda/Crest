import SwiftUI

struct BrowserDetailView: View {
    let presentation: BrowserPageSurfacePresentation
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool
    var previewsStartPage = false

    var body: some View {
        let tab = presentation.singleTab
        let page = selectedPage(for: tab)
        BrowserDetailContent(
            page: page,
            tab: tab,
            space: presentation.presentingSpace,
            pagePresentation: previewsStartPage ? .startPage : pagePresentation(for: page, tab: tab),
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            tabPromotionNamespace: tabPromotionNamespace,
            startPageFocusRequest: startPageFocusRequest,
            isCommandPalettePresented: isCommandPalettePresented
        )
    }

    private func pagePresentation(
        for page: BrowserPage?,
        tab: BrowserTab?
    ) -> BrowserPagePresentation {
        BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: tab.map { $0.pagePresentationSelection }
                    ?? .none,
                hasActivePage: page != nil,
                hasNavigationFailure: page?.navigationFailure != nil,
                hasProcessFailure: page?.webContentFailureMessage != nil,
                unloadedBehavior: .remainUnloaded
            )
        )
    }

    private func selectedPage(for tab: BrowserTab?) -> BrowserPage? {
        guard let tab,
            let space = presentation.presentingSpace
        else { return nil }
        return pages.surfacePage(for: tab, in: space, accessController: spaceAccess)
    }
}
