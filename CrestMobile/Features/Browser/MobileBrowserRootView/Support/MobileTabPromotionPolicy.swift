enum MobileTabPromotionPolicy {
    static let usesNativeNavigationTransition = true

    static func supports(_ placement: TabPlacement) -> Bool {
        switch placement {
        case .pinned, .saved, .current:
            true
        }
    }

    static func destinationID(for tabID: TabID) -> String {
        BrowserTabPromotionID.value(for: tabID)
    }

    static func isTransitionSource(
        _ tab: BrowserTab,
        selectedTabID: TabID?
    ) -> Bool {
        tab.id == selectedTabID
            && !tab.isStartPage
            && supports(tab.placement)
    }

    static func target(
        for tab: BrowserTab?,
        selectedTabID: TabID?
    ) -> MobileTabPromotionTarget? {
        guard let tab,
            isTransitionSource(tab, selectedTabID: selectedTabID)
        else {
            return nil
        }
        return MobileTabPromotionTarget(
            tabID: tab.id,
            placement: tab.placement
        )
    }

    static func shouldPreposition(
        previous: MobileTabPromotionTarget?,
        current: MobileTabPromotionTarget?,
        compactPageIsFullyPresented: Bool
    ) -> Bool {
        compactPageIsFullyPresented && current != nil && previous != current
    }
}
