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

enum MobileBrowserSpaceSwitchPolicy {
    static func destinationAfterLeavingLockedSpace(
        in presentation: MobileBrowserPresentation,
        sidebarPresentation: BrowserSidebarPresentation
    ) -> MobileBrowserSpaceSwitchDestination {
        presentation == .compact && sidebarPresentation == .docked
            ? .tabViewer
            : .selectedPage
    }
}

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
        BrowserTabPromotionSourcePolicy.isPromotionSource(
            tab,
            isSelected: tab.id == selectedTabID
        ) && supports(tab.placement)
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
