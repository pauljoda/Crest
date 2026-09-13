import Foundation

/// Promotes an authorized transient URL and delegates live-page adoption to its adapter.
struct BrowserTransientPagePromotion {
    let url: URL
    let sourceAssignment: BrowserSpaceRuntimeAssignment
    let leaseAssignment: BrowserSpaceRuntimeAssignment
    let destinationAssignment: BrowserSpaceRuntimeAssignment

    enum Outcome {
        case adoptedLivePage
        case openedNewPage
    }

    @MainActor
    func perform(
        in browser: BrowserStore,
        isLocked: @MainActor (BrowserSpace) -> Bool,
        adoptPage: (TabID, BrowserSpace) -> Bool
    ) -> Outcome? {
        guard leaseAssignment == sourceAssignment,
            let promotion = BrowserTransientSessionPolicy.promotionSpaces(
                source: browser.space(matching: sourceAssignment),
                destination: browser.space(matching: destinationAssignment),
                isLocked: isLocked
            ),
            let tabID = browser.openNewTab(url: url, matching: destinationAssignment),
            let currentDestination = browser.space(
                matching: BrowserSpaceRuntimeAssignment(space: promotion.destination))
        else { return nil }

        let adoptedLivePage =
            BrowserTransientSessionPolicy.adoptsLivePage(
                leaseAssignment: leaseAssignment, destination: currentDestination)
            && adoptPage(tabID, currentDestination)
        return adoptedLivePage ? .adoptedLivePage : .openedNewPage
    }
}
