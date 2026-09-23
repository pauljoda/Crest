import SwiftUI

struct BrowserDetailContent: View {
    let page: BrowserPage?
    /// The tab this content is rendering. The single-page path passes the
    /// selected tab; a Split View card passes its own member, which is what
    /// keeps an unfocused start-page card bound to itself.
    let tab: BrowserTab?
    let space: BrowserSpace?
    let pagePresentation: BrowserPagePresentation
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool

    var body: some View {
        if let tab, let space, !spaceAccess.isLocked(space), pages.isMirroringPage(for: tab.id) {
            BrowserMirroredPageContent(tabID: tab.id, pages: pages)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch pagePresentation {
        case .noSelection:
            Color.clear
        case .nativeContent:
            if let tab, let space {
                BrowserNativeTabHost(tab: tab, space: space)
                    .environment(\.browserNativeTabs, pages.nativeTabs)
                    .environment(
                        \.browserNativeTabActions,
                        BrowserNativeTabActions(
                            browser: browser, spaceAccess: spaceAccess,
                            didOpenURL: { pages.select(session: browser.presented) }))
            }
        case .startPage:
            BrowserStartPageContent(
                tab: tab,
                space: space,
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
