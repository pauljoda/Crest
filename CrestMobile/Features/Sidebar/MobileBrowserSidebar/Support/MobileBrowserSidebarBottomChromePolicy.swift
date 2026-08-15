import Foundation

enum MobileBrowserSidebarBottomChromePolicy {
    static func placement(
        for mode: MobileBrowserSidebarMode,
        isVisible: Bool
    ) -> MobileBrowserSidebarBottomChromePlacement {
        return switch mode {
        case .compactTabViewer:
            // Keep the inset in the compact owner while its controls are
            // absent. That leaves the selected matched tab destination at the
            // same resting position throughout page presentation and return.
            .inlineSafeAreaInset
        case .regularSidebar:
            isVisible ? .inlineSafeAreaInset : .hidden
        }
    }

    static func content(
        for mode: MobileBrowserSidebarMode,
        isVisible: Bool
    ) -> MobileBrowserSidebarBottomChromeContent {
        if mode == .compactTabViewer, !isVisible {
            return .reservedSpace
        }
        return .actions
    }
}
