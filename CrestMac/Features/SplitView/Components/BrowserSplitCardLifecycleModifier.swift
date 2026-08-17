import SwiftUI

/// Keeps an **unfocused** Split View card's tab and history in step with its own
/// page.
///
/// `BrowserRootLifecycleModifier` observes `pages.activePage` and means "the
/// focused card" everywhere — that is the whole reason focus rides selection and
/// no second focus state exists. It is also why an unfocused card had nobody
/// watching it: a neighbour could navigate to three pages and its sidebar row
/// would still read whatever it said when the card appeared, with none of those
/// pages recorded in history.
///
/// Focused cards are excluded rather than merged, so the root observers keep sole
/// ownership of the focused page and no navigation is recorded twice. The guard
/// reads `pages.activeTabID` rather than a passed-in flag because the pool is the
/// authority on which card is focused and a view's copy can be a frame behind.
///
/// The observation set is the metadata half of the root's seven observers. Chrome
/// concerns are deliberately absent: the address field, the security indicator,
/// and the extension-activity sweep all speak for the focused card by definition,
/// and an unfocused card has no business writing to them.
struct BrowserSplitCardLifecycleModifier: ViewModifier {
    let tab: BrowserTab
    let space: BrowserSpace
    let page: BrowserPage?
    let browser: BrowserStore
    let pages: BrowserPagePool

    func body(content: Content) -> some View {
        content
            .onChange(of: page?.displayURL) {
                synchronizePageMetadata()
            }
            .onChange(of: page?.title) {
                synchronizePageMetadata()
            }
            .onChange(of: page?.faviconData) {
                synchronizePageMetadata()
            }
            .onChange(of: page?.themeColor) {
                synchronizePageMetadata()
            }
            .onChange(of: page?.completedNavigationCount) {
                recordCompletedNavigation()
            }
    }

    private var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(space: space)
    }

    /// True only while some other card holds focus. A card that gains focus stops
    /// reporting here in the same frame the root observers take it over.
    private var isUnfocusedCard: Bool {
        pages.activeTabID != tab.id
    }

    private func synchronizePageMetadata() {
        guard isUnfocusedCard, let page else { return }
        browser.updateTabFromPage(
            url: page.displayURL,
            title: page.navigationFailure?.displayHost ?? page.title,
            faviconData: page.faviconData,
            iconAccent: page.siteThemeIconAccent,
            for: tab.id,
            matching: assignment
        )
    }

    private func recordCompletedNavigation() {
        guard isUnfocusedCard, let page, let url = page.url else { return }
        synchronizePageMetadata()
        browser.recordVisit(url: url, title: page.title, matching: assignment)
        // Re-read the Space so the restyle sees the visit just recorded, and
        // restyle every presented card: the neighbour showing the same link is
        // the card that most needs to know it has now been followed.
        guard let visitedSpace = browser.space(matching: assignment) else { return }
        Task { await pages.styleVisitedLinks(in: visitedSpace) }
    }
}
