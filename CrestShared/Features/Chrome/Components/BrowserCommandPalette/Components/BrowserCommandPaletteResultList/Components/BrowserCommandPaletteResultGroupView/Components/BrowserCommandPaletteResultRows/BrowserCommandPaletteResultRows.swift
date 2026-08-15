import SwiftUI

struct BrowserCommandPaletteResultRows: View {
    let model: BrowserCommandPaletteModel
    let items: [BrowserCommandPaletteIndexedResult]

    var body: some View {
        ForEach(items) { item in
            if item.result.isIntent {
                BrowserCommandPaletteIntentRow(model: model, item: item)
            } else {
                BrowserCommandPaletteResultRow(model: model, item: item)
            }
        }
    }
}

#Preview("Command Palette Result Rows") {
    @Previewable @State var model = BrowserCommandPalettePreviewFixture.model(
        query: "swift"
    )

    BrowserCommandPaletteResultRows(
        model: model,
        items: BrowserCommandPalettePreviewFixture.mixedItems
    )
    .frame(width: BrowserCommandPaletteMetrics.maximumCardWidth)
    .padding(CrestSpacing.large)
}
