import SwiftUI

struct BrowserCommandPaletteResultRow: View {
    let model: BrowserCommandPaletteModel
    let item: BrowserCommandPaletteIndexedResult

    var body: some View {
        Button {
            model.activate(item.result)
        } label: {
            HStack(spacing: BrowserCommandPaletteMetrics.rowSpacing) {
                BrowserCommandPaletteRowIcon(model: model, result: item.result)

                VStack(
                    alignment: .leading,
                    spacing: BrowserCommandPaletteMetrics.rowTextSpacing
                ) {
                    Text(verbatim: item.result.title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if !item.result.subtitle.isEmpty {
                        Text(verbatim: item.result.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: BrowserCommandPaletteMetrics.rowSpacing)

                BrowserCommandPaletteRowTrailing(model: model, result: item.result)

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(
            BrowserCommandPaletteRowButtonStyle(
                isSelected: model.selectedResultIndex == item.index
            )
        )
        .accessibilityIdentifier("command-palette-result-\(item.index)")
        .browserCommandPaletteHoverSelection(model: model, index: item.index)
    }
}

#if DEBUG
    #Preview("Tab and command results") {
        let model = BrowserCommandPalettePreviewFixture.model(query: "swift")
        VStack(spacing: 4) {
            BrowserCommandPaletteResultRow(model: model, item: BrowserCommandPalettePreviewFixture.tabItem)
            BrowserCommandPaletteResultRow(model: model, item: BrowserCommandPalettePreviewFixture.commandItem)
        }.padding().frame(width: 600)
    }
#endif
