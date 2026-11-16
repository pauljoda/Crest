import SwiftUI

extension View {
    /// Applies folder indentation and density while allowing accessible text to grow.
    func browserSavedFolderHeaderLayout(
        configuration: BrowserFolderGroupConfiguration
    ) -> some View {
        browserFolderHeaderLayout(
            metrics: configuration.headerMetrics, leadingInset: configuration.headerLeadingInset,
            trailingInset: configuration.headerTrailingInset)
    }

    /// Lays out a header that stands as a folder's does, such as a Split
    /// View's: `metrics` for its height, starting `leadingInset` in and
    /// ending `trailingInset`, or the metrics' own, short of its trailing edge.
    func browserFolderHeaderLayout(
        metrics: BrowserFolderHeaderMetrics, leadingInset: CGFloat, trailingInset: CGFloat? = nil
    ) -> some View {
        modifier(
            BrowserFolderHeaderDensityLayout(
                metrics: metrics, leadingInset: leadingInset,
                trailingInset: trailingInset ?? metrics.contentTrailingInset))
    }
}

private struct BrowserFolderHeaderDensityLayout: ViewModifier {
    let metrics: BrowserFolderHeaderMetrics
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tabScale: Double { BrowserDeviceAppearanceStore.shared.tabScale }

    func body(content: Content) -> some View {
        let rowHeight = BrowserSidebarDensity(dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale)
            .rowHeight(base: CrestLayout.sidebarRowHeight, touch: !metrics.usesFixedRowHeight)
        let height = BrowserFolderLayout.headerHeight(rowHeight: rowHeight, minimum: metrics.iconWidth)
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
            .frame(
                minHeight: height,
                maxHeight: metrics.usesFixedRowHeight && !dynamicTypeSize.isAccessibilitySize
                    ? height
                    : nil
            )
    }
}
