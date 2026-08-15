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

#Preview("Command Palette Row Icons") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )

    HStack(spacing: CrestSpacing.extraLarge) {
        VStack(spacing: CrestSpacing.small) {
            BrowserCommandPaletteRowIcon(
                model: model,
                result: BrowserCommandPalettePreviewFixture.tabResult
            )
            Text("Tab")
                .font(.caption)
        }

        VStack(spacing: CrestSpacing.small) {
            BrowserCommandPaletteRowIcon(
                model: model,
                result: BrowserCommandPalettePreviewFixture.commandResult
            )
            Text("Command")
                .font(.caption)
        }
    }
    .padding(CrestSpacing.large)
}
