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
            } else if let provider = result.searchProvider {
                BrowserSearchProviderIcon(
                    provider: provider,
                    profileID: model.space?.profile.id,
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

#if DEBUG
    #Preview("Result icons") {
        let model = BrowserCommandPalettePreviewFixture.model(query: "swift")
        HStack(spacing: 20) {
            BrowserCommandPaletteRowIcon(model: model, result: BrowserCommandPalettePreviewFixture.intentResult)
            BrowserCommandPaletteRowIcon(model: model, result: BrowserCommandPalettePreviewFixture.tabResult)
            BrowserCommandPaletteRowIcon(model: model, result: BrowserCommandPalettePreviewFixture.commandResult)
        }.padding()
    }
#endif
