import SwiftUI

struct BrowserDetailContent: View {
    let page: BrowserPage?
    /// The tab this content is rendering. The single-page path passes the
    /// selected tab; a Split View card passes its own member, which is what
    /// keeps an unfocused start-page card bound to itself.
    let tab: BrowserTab?
    let pagePresentation: BrowserPagePresentation
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let isCommandPalettePresented: Bool

    var body: some View {
        switch pagePresentation {
        case .noSelection:
            ContentUnavailableView(
                "No Tab Selected",
                systemImage: "rectangle.on.rectangle.slash",
                description: Text("Create a tab or choose one from the sidebar.")
            )
        case .startPage:
            BrowserStartPageContent(
                tab: tab,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                tabPromotionNamespace: tabPromotionNamespace,
                isCommandPalettePresented: isCommandPalettePresented
            )
        case .livePage, .navigationFailure, .processFailure:
            BrowserLivePageContent(
                page: page,
                browser: browser,
                pages: pages
            )
        case .unloaded, .automaticRestore:
            BrowserUnloadedPageSurface()
        }
    }
}
