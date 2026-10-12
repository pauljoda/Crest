import Foundation

enum MobileBrowserRootSelectionChange: Equatable, Sendable {
    case unchanged
    case tab
    case space
    case profile

    static func resolve(
        from previous: MobileBrowserRootSelectionSnapshot,
        to current: MobileBrowserRootSelectionSnapshot
    ) -> Self {
        if previous.selectedSpaceID != current.selectedSpaceID {
            return .space
        }
        if previous.selectedProfileID != current.selectedProfileID {
            return .profile
        }
        if previous.assignment?.tabID != current.assignment?.tabID {
            return .tab
        }
        return .unchanged
    }
}

enum MobileTabPromotionPolicy {
    static let usesNativeNavigationTransition = true

    static func destinationID(for tabID: UUID) -> String {
        BrowserTabPromotionID.value(for: tabID)
    }

    @MainActor
    static func isTransitionSource(_ tab: TabStateModel, selectedTabID: UUID?) -> Bool {
        BrowserTabPromotionSourcePolicy.isPromotionSource(tab, isSelected: tab.id == selectedTabID)
    }

    /// The target the shown tab of the read model promotes from: the tab the
    /// window shows, unless it is a Start Page, which has no row.
    @MainActor
    static func target(for shownTab: TabStateModel) -> MobileTabPromotionTarget? {
        guard !shownTab.isStartPage else { return nil }
        return MobileTabPromotionTarget(tabID: shownTab.id, placement: shownTab.placement)
    }

    static func shouldPreposition(
        previous: MobileTabPromotionTarget?,
        current: MobileTabPromotionTarget?,
        compactPageIsFullyPresented: Bool
    ) -> Bool {
        compactPageIsFullyPresented && current != nil && previous != current
    }
}
