import SwiftUI

/// The shipped layout metrics for a Settings pane header on each shell.
struct BrowserSettingsPaneHeaderLayout: Equatable {
    var iconSize: CGFloat
    var symbolSize: CGFloat
    var cornerRadius: CGFloat
    /// Between the tile and the title.
    var iconSpacing: CGFloat
    var horizontalPadding: CGFloat
    var topPadding: CGFloat
    var bottomPadding: CGFloat
    var scalesIconWithDynamicType: Bool

    /// Centred above the detail pane's scroll content, sized against the
    /// Settings window's own point metrics.
    static let macOSPage = BrowserSettingsPaneHeaderLayout(
        iconSize: BrowserSettingsVisualPolicy.pageIconSize,
        symbolSize: 21,
        cornerRadius: CrestRadius.control,
        iconSpacing: CrestSpacing.small,
        horizontalPadding: CrestSpacing.section,
        topPadding: CrestSpacing.extraExtraLarge,
        bottomPadding: CrestSpacing.extraLarge,
        scalesIconWithDynamicType: false
    )

    /// The first, chrome-less row of a grouped `Form`. These are the metrics iOS
    /// has shipped since the header existed.
    static let mobilePage = BrowserSettingsPaneHeaderLayout(
        iconSize: 58,
        symbolSize: 25,
        cornerRadius: 15,
        iconSpacing: CrestSpacing.medium,
        horizontalPadding: 28,
        topPadding: CrestSpacing.large,
        bottomPadding: CrestSpacing.large,
        scalesIconWithDynamicType: true
    )
}
