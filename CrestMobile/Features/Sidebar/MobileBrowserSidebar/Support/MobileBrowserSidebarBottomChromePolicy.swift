import Foundation

enum MobileBrowserSidebarBottomChromePolicy {
    /// Where the bottom chrome sits.
    ///
    /// A shell that reserves the inset keeps it whether or not its controls are
    /// on screen. That leaves the selected matched tab destination at the same
    /// resting position throughout page presentation and return.
    static func placement(
        reservesInset: Bool,
        isVisible: Bool
    ) -> MobileBrowserSidebarBottomChromePlacement {
        if reservesInset {
            return .inlineSafeAreaInset
        }
        return isVisible ? .inlineSafeAreaInset : .hidden
    }

    static func content(
        reservesInset: Bool,
        isVisible: Bool
    ) -> MobileBrowserSidebarBottomChromeContent {
        if reservesInset, !isVisible {
            return .reservedSpace
        }
        return .actions
    }
}
