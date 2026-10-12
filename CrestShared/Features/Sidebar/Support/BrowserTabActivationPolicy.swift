import Foundation

/// Selects the tab before presenting its destination.
enum BrowserTabActivationPolicy {
    enum Destination {
        case page
        case settings
    }

    static func activate(
        _ tabID: UUID,
        selectTab: (UUID) -> Void,
        presentPage: () -> Void
    ) {
        selectTab(tabID)
        presentPage()
    }
}
