import SwiftUI

struct BrowserDetailView: View {
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let startPageFocusRequest: Int
    let isCommandPalettePresented: Bool

    var body: some View {
        let page = selectedPage
        BrowserDetailContent(
            page: page,
            tab: browser.selectedTab,
            pagePresentation: pagePresentation(for: page),
            browser: browser,
            pages: pages,
            spaceAccess: spaceAccess,
            tabPromotionNamespace: tabPromotionNamespace,
            startPageFocusRequest: startPageFocusRequest,
            isCommandPalettePresented: isCommandPalettePresented
        )
    }

    private func pagePresentation(
        for page: BrowserPage?
    ) -> BrowserPagePresentation {
        BrowserPagePresentationPolicy.resolve(
            BrowserPagePresentationInput(
                selection: selectionPresentation,
                hasActivePage: page != nil,
                hasNavigationFailure: page?.navigationFailure != nil,
                hasProcessFailure: page?.webContentFailureMessage != nil,
                unloadedBehavior: .remainUnloaded
            )
        )
    }

    private var selectionPresentation: BrowserPagePresentationSelection {
        guard let tab = browser.selectedTab else { return .none }
        return tab.isStartPage ? .startPage : .webPage
    }

    private var selectedPage: BrowserPage? {
        guard let tab = browser.selectedTab,
            let space = browser.selectedSpace
        else { return nil }
        return pages.activePage(
            matching: BrowserTabRuntimeAssignment(
                tabID: tab.id,
                spaceID: space.id,
                profileID: space.profile.id
            )
        )
    }
}
