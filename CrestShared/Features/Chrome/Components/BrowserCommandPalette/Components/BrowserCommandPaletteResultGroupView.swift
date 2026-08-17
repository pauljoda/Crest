import SwiftUI

struct BrowserCommandPaletteResultGroupView: View {
    let model: BrowserCommandPaletteModel
    let group: BrowserCommandPaletteResultGroup

    @ViewBuilder
    var body: some View {
        if let header = group.header {
            VStack(
                alignment: .leading,
                spacing: BrowserCommandPaletteMetrics.resultHeaderSpacing
            ) {
                Text(LocalizedStringKey(header))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(
                        .horizontal,
                        BrowserCommandPaletteMetrics.resultHeaderHorizontalPadding
                    )
                BrowserCommandPaletteResultRows(model: model, items: group.items)
            }
        } else {
            BrowserCommandPaletteResultRows(model: model, items: group.items)
        }
    }
}
