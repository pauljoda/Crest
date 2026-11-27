import SwiftUI

struct BrowserDetailView: View {
    let presentation: BrowserPageSurfacePresentation
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let chrome: BrowserChromeState
    /// Builds the window's commands lazily, only when a Start Page renders.
    let makeCommands: () -> BrowserCommandPaletteCommandRegistry
    var previewsStartPage = false

    var body: some View {
        let tab = presentation.singleTab
        let space = presentation.presentingSpace
        let page = tab.flatMap { tab in
            space.flatMap { pages.surfacePage(for: tab.id, in: $0, accessController: spaceAccess) }
        }
        BrowserDetailContent(
            page: page,
            tab: tab,
            space: space,
            pagePresentation: previewsStartPage ? .startPage : .of(tab?.surface, page: page),
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            tabPromotionNamespace: tabPromotionNamespace,
            chrome: chrome,
            makeCommands: makeCommands
        )
    }
}
