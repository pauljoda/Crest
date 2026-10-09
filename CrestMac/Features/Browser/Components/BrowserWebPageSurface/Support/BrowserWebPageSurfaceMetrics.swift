import CoreGraphics

enum BrowserWebPageSurfaceMetrics {
    static let overlayPadding = CrestSpacing.medium
    static let infoBarSpacing: CGFloat = 8
    static let infoBarHorizontalPadding: CGFloat = 14
    static let infoBarVerticalPadding: CGFloat = 10
    static let infoBarMaximumWidth: CGFloat = 640
    static let infoBarCornerRadius: CGFloat = 16
    static let initialLoadingSpacing = CrestSpacing.small
    static let loadingProgressHeight: CGFloat = 2
    static let regionCaptureZIndex: Double = 20
    static let sharePickerZIndex: Double = 25
    /// The share picker uses the page prompts' panel: the permission prompt's
    /// header and spacing, the credential prompt's surface and rows.
    static let sharePickerWidth: CGFloat = 360
    static let sharePickerPadding: CGFloat = 14
    static let sharePickerSpacing = CrestSpacing.medium
    static let sharePickerStrokeWidth: CGFloat = 0.5
    static let sharePickerShadowRadius: CGFloat = 14
    static let sharePickerShadowOffset: CGFloat = 6
    static let sharePickerHeaderSpacing: CGFloat = 10
    static let sharePickerHeaderIconSize: CGFloat = 24
    static let sharePickerCloseControlSize: CGFloat = 28
    static let infoBarMinimizeControlSize: CGFloat = 24
    static let sharePickerHeaderTextSpacing: CGFloat = 3
    static let sharePickerListMaximumHeight: CGFloat = 264
    static let sharePickerRowSpacing: CGFloat = 10
    static let sharePickerRowIconSize: CGFloat = 17
    static let sharePickerRowTextSpacing: CGFloat = 1
    static let sharePickerListRowSpacing: CGFloat = 2
    static let sharePickerRowVerticalPadding: CGFloat = 7
    static let sharePickerRowHighlightBleed: CGFloat = 8
    static let sharePickerCornerRadius = CrestRadius.card
    /// A row's highlight is concentric with the panel's corner: the panel's
    /// radius less the highlight's inset from the panel's edge, so the margin
    /// around the corner stays even.
    static let sharePickerRowHighlightCornerRadius =
        sharePickerCornerRadius - (sharePickerPadding - sharePickerRowHighlightBleed)
    static let feedbackZIndex: Double = 30
    static let feedbackHorizontalPadding: CGFloat = 14
    static let feedbackHeight: CGFloat = 38
    static let feedbackShadowOpacity = 0.18
    static let feedbackShadowRadius: CGFloat = 14
    static let feedbackShadowY: CGFloat = 6
    static let feedbackTopPadding = CrestSpacing.medium
}
