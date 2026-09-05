import SwiftUI

/// The folder's symbol, in the same column the rows below give their favicons.
struct BrowserFolderIcon: View {
    let folder: BrowserFolder
    let isExpanded: Bool
    let metrics: BrowserFolderHeaderMetrics

    var body: some View {
        Image(
            systemName: BrowserFolderRowPresentationPolicy.systemImage(
                isExpanded: isExpanded
            )
        )
        .modifier(BrowserFolderIconColumn(metrics: metrics))
        .foregroundStyle(folder.color.color.opacity(0.86))
        .accessibilityHidden(true)
    }
}

/// Holds the symbol in its column, and sizes it where the shell reads the row
/// from further away than a desk.
private struct BrowserFolderIconColumn: ViewModifier {
    let metrics: BrowserFolderHeaderMetrics

    @ViewBuilder
    func body(content: Content) -> some View {
        if let glyphSize = metrics.iconGlyphSize {
            content
                .font(
                    .system(size: glyphSize, weight: metrics.iconGlyphWeight)
                )
                .frame(width: metrics.iconWidth)
        } else {
            content.frame(width: metrics.iconWidth)
        }
    }
}
