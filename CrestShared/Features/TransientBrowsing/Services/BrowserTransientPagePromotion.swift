import Foundation

/// Promotes an authorized transient URL and delegates live-page adoption to its adapter.
struct BrowserTransientPagePromotion {
    let requestID: UUID
    let url: URL?
    let sourceAssignment: BrowserSpaceRuntimeAssignment
    let leaseAssignment: BrowserSpaceRuntimeAssignment?
    let destinationAssignment: BrowserSpaceRuntimeAssignment
    var supportsLiveAdoption = true

    enum Outcome {
        case adoptedLivePage
        case openedNewPage
        case selectedSpace
    }

    @MainActor
    func perform(
        in browser: BrowserStore,
        isLocked: @MainActor (BrowserSpace) -> Bool,
        adoptPage: (TabID, BrowserSpace) -> Bool
    ) -> Outcome? {
        guard let source = browser.space(matching: sourceAssignment),
            let destination = browser.space(matching: destinationAssignment),
            let promotion = browser.promoteTransientPage(requestID: requestID, url: url,
                source: sourceAssignment, lease: leaseAssignment, destination: destinationAssignment,
                sourceAccessible: !isLocked(source), destinationAccessible: !isLocked(destination),
                supportsLiveAdoption: supportsLiveAdoption)
        else { return nil }
        guard let tabID = promotion.tabID else { return .selectedSpace }
        guard let currentDestination = browser.space(matching: destinationAssignment) else { return nil }
        let adoptedLivePage = promotion.adoptLivePage && adoptPage(tabID, currentDestination)
        return adoptedLivePage ? .adoptedLivePage : .openedNewPage
    }
}
