import CoreGraphics

enum BrowserRootMetrics {
    static let utilityFanAdditionalEdgeOffset: CGFloat = 12
    static let sidebarResizeHandleOffset: CGFloat = 8
    static let collapsedSidebarRevealWidth: CGFloat = 14
    static let floatingSidebarBorderWidth: CGFloat = 0.75
    static let floatingSidebarBorderOpacity = 0.2
    static let floatingSidebarShadowRadius: CGFloat = 28
    static let floatingSidebarShadowOffset: CGFloat = 8
    static let floatingSidebarShadowOpacity = 0.3
    static let floatingSidebarHighlightOpacity = CrestOpacity.chromeSurface
    static let floatingSidebarShadeOpacity = 0.09
    static let urlCopyFeedbackHorizontalPadding: CGFloat = 14
    static let urlCopyFeedbackHeight: CGFloat = 40
    static let urlCopyFeedbackShadowRadius: CGFloat = 16
    static let urlCopyFeedbackShadowYOffset: CGFloat = 8
    static let urlCopyFeedbackTopInset: CGFloat = 18
    static let urlCopyFeedbackDuration: Duration = .milliseconds(1_400)
    static let sidebarResizeControlZIndex: Double = 3
    static let floatingSidebarZIndex: Double = 4
    static let utilityFanZIndex: Double = 8
    static let commandPaletteZIndex: Double = 10
    static let peekZIndex: Double = 20
    static let feedbackZIndex: Double = 30
}
