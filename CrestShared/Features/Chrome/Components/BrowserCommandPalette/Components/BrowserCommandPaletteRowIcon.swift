import SwiftUI

struct BrowserCommandPaletteRowIcon: View {
    let model: BrowserCommandPaletteModel
    let result: BrowserCommandPaletteResult

    var body: some View {
        Group {
            if let tab = model.tab(for: result) {
                TabFaviconView(
                    tab: tab,
                    profileID: model.profileID(for: result),
                    size: BrowserCommandPaletteMetrics.rowFaviconSize
                )
            } else {
                Image(systemName: result.symbol)
                    .font(
                        .system(
                            size: BrowserCommandPaletteMetrics.rowSymbolPointSize,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.secondary)
            }
        }
        .frame(
            width: BrowserCommandPaletteMetrics.rowIconContainerSize,
            height: BrowserCommandPaletteMetrics.rowIconContainerSize
        )
        .background(
            .primary.opacity(BrowserCommandPaletteMetrics.rowIconBackgroundOpacity),
            in: .rect(cornerRadius: BrowserCommandPaletteMetrics.rowIconCornerRadius)
        )
    }
}
