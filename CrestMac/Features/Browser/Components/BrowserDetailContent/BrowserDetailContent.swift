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
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool

    var body: some View {
        switch pagePresentation {
        case .noSelection:
            Color.clear
        case .nativeContent:
            if let tab, let space = browser.selectedSpace {
                BrowserNativeTabHost(tab: tab, space: space)
                    .environment(
                        \.browserNativeTabActions,
                        BrowserNativeTabActions(
                            browser: browser, spaceAccess: spaceAccess,
                            didOpenURL: { pages.select(session: browser.session) }))
            }
        case .startPage:
            BrowserStartPageContent(
                tab: tab,
                browser: browser,
                pages: pages,
                spaceAccess: spaceAccess,
                tabPromotionNamespace: tabPromotionNamespace,
                focusRequest: startPageFocusRequest,
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
