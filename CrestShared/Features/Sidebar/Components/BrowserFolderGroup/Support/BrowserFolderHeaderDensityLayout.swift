import SwiftUI

extension View {
    /// Applies folder indentation and density while allowing accessible text to grow.
    func browserSavedFolderHeaderLayout(
        configuration: BrowserFolderGroupConfiguration
    ) -> some View {
        modifier(BrowserFolderHeaderDensityLayout(configuration: configuration))
    }
}

private struct BrowserFolderHeaderDensityLayout: ViewModifier {
    let configuration: BrowserFolderGroupConfiguration
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(BrowserSidebarDensityPreference.scaleKey, store: BrowserSidebarDensityPreference.defaults) private
        var tabScale = 1.0

    func body(content: Content) -> some View {
        let metrics = configuration.headerMetrics
        let height = BrowserSidebarDensityPolicy.rowHeight(
            base: CrestLayout.sidebarRowHeight,
            scale: dynamicTypeSize.isAccessibilitySize ? max(1, tabScale) : tabScale,
            touch: !metrics.usesFixedRowHeight)
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, configuration.headerLeadingInset)
            .padding(.trailing, metrics.contentTrailingInset)
            .frame(
                minHeight: height,
                maxHeight: metrics.usesFixedRowHeight && !dynamicTypeSize.isAccessibilitySize
                    ? height
                    : nil
            )
    }
}
