import SwiftUI

extension View {
    /// Places a saved folder header's content: indented to the folder's depth,
    /// held off the trailing edge, and either a band of one exact height or a
    /// row that grows with its title.
    func browserSavedFolderHeaderLayout(
        configuration: BrowserSavedFolderGroupConfiguration
    ) -> some View {
        let metrics = configuration.headerMetrics
        return frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, configuration.headerLeadingInset)
            .padding(.trailing, metrics.contentTrailingInset)
            .frame(
                minHeight: CrestLayout.sidebarRowHeight,
                maxHeight: metrics.usesFixedRowHeight
                    ? CrestLayout.sidebarRowHeight
                    : nil
            )
    }
}
