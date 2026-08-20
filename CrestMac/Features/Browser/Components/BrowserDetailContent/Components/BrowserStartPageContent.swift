import SwiftUI

struct BrowserStartPageContent: View {
    /// The tab this start page belongs to.
    ///
    /// Split View renders one of these per card, so the surface can no longer
    /// assume it is speaking for the selected tab. Every action still routes
    /// through `BrowserCommandPaletteActionPolicy`, which answers "unavailable"
    /// for a card that is not the focused one — an unfocused start page reads
    /// but does not act until a click makes it the focused card.
    let tab: BrowserTab?
    let browser: BrowserStore
    let pages: BrowserPagePool
    let spaceAccess: BrowserSpaceAccessController
    let tabPromotionNamespace: Namespace.ID
    let isCommandPalettePresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let tab {
            BrowserStartPage(
                space: browser.selectedSpace,
                isPrivateBrowsing: browser.isPrivateBrowsing,
                selectedTabID: tab.id,
                isSourceAvailable: isSourceAvailable,
                selectTab: selectStartPageTab,
                openURL: openStartPageURL,
                promotionNamespace: tabPromotionNamespace,
                promotionID: BrowserTabPromotionID.value(for: tab.id),
                isCommandPaletteObscured: isCommandPalettePresented
            )
        } else {
            BrowserUnloadedPageSurface()
        }
    }

    private func openStartPageURL(
        _ source: BrowserTabRuntimeAssignment,
        _ url: URL
    ) -> Bool {
        guard isSourceAvailable(source) else { return false }
        withAnimation(
            BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.contentNavigation,
                reduceMotion: reduceMotion
            )
        ) {
            browser.navigateSelectedTab(to: url)
            pages.load(url)
        }
        return true
    }

    private func selectStartPageTab(
        _ source: BrowserTabRuntimeAssignment,
        _ target: BrowserTabRuntimeAssignment
    ) -> Bool {
        guard
            let destination = BrowserCommandPaletteActionPolicy.target(
                target,
                from: source,
                in: browser,
                accessController: spaceAccess
            )
        else { return false }
        browser.selectSpace(destination.space.id)
        browser.selectTab(destination.tab.id)
        pages.select(session: browser.session)
        return true
    }

    private func isSourceAvailable(
        _ source: BrowserTabRuntimeAssignment
    ) -> Bool {
        BrowserCommandPaletteActionPolicy.isSourceAvailable(
            source,
            in: browser,
            accessController: spaceAccess
        )
    }
}
