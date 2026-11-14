import SwiftUI

extension View {
    /// Applies folder indentation and density while allowing accessible text to grow.
    func browserSavedFolderHeaderLayout(
        configuration: BrowserFolderGroupConfiguration
    ) -> some View {
        browserFolderHeaderLayout(metrics: configuration.headerMetrics, leadingInset: configuration.headerLeadingInset)
    }

    /// Lays out a header that stands as a folder's does, such as a Split
    /// View's: `metrics` for its height and trailing edge, starting
    /// `leadingInset` in.
    func browserFolderHeaderLayout(metrics: BrowserFolderHeaderMetrics, leadingInset: CGFloat) -> some View {
        modifier(BrowserFolderHeaderDensityLayout(metrics: metrics, leadingInset: leadingInset))
    }
}

private struct BrowserFolderHeaderDensityLayout: ViewModifier {
    let metrics: BrowserFolderHeaderMetrics
    let leadingInset: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        let rowHeight = BrowserSidebarDensity(dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale)
            .rowHeight(base: CrestLayout.sidebarRowHeight, touch: !metrics.usesFixedRowHeight)
        let height = BrowserFolderLayout.headerHeight(rowHeight: rowHeight, minimum: metrics.iconWidth)
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leadingInset)
            .padding(.trailing, metrics.contentTrailingInset)
            .frame(
                minHeight: height,
                maxHeight: metrics.usesFixedRowHeight && !dynamicTypeSize.isAccessibilitySize
                    ? height
                    : nil
            )
    }
}
