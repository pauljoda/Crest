import CoreGraphics

/// Feature-specific chrome geometry; cross-feature hit targets come from `CrestLayout`.
enum MobileBrowserChromeLayout {
    static let compactToolbarSpacing: CGFloat = 8
    static let compactToolbarHorizontalPadding: CGFloat = 10
    static let compactToolbarVerticalPadding: CGFloat = 6
    static let compactToolbarSymbolSize: CGFloat = 16

    static let collapsedSidebarRevealWidth: CGFloat = 26
    static let collapsedSidebarGestureDistance: CGFloat = 10
    static let collapsedSidebarControlPadding: CGFloat = 10

    static let findItemSpacing: CGFloat = 6
    static let findLeadingPadding: CGFloat = 14
    static let findTrailingPadding: CGFloat = 4
    static let findStatusWidth: CGFloat = 24
    static let findButtonWidth: CGFloat = 40
    static let findShadowOpacity = 0.14
    static let findShadowRadius: CGFloat = 12
    static let findShadowOffset: CGFloat = 5
    static let regularFindMaximumWidth: CGFloat = 440
    static let compactFindHorizontalPadding: CGFloat = 10
    static let regularFindHorizontalPadding: CGFloat = 12
    static let regularFindTopPadding: CGFloat = 12
    static let compactFindToolbarGap: CGFloat = 14
    static let findFallbackBottomPadding: CGFloat = 12

    static let historyDividerHeight: CGFloat = 18
    static let historyDividerOpacity = 0.24
    static let historyCapsuleHorizontalPadding: CGFloat = 2

    static let regularStartPageSpacing: CGFloat = 28
    static let regularStartPagePadding: CGFloat = 40
    static let regularStartPageMaximumWidth: CGFloat = 820
    static let compactStartPageSpacing: CGFloat = 22
    static let compactStartPagePadding: CGFloat = 24
    static let compactStartPageMaximumWidth: CGFloat = 620
    static let startPageMarkSize: CGFloat = 48
    static let privateNoticeSpacing: CGFloat = 6
}
