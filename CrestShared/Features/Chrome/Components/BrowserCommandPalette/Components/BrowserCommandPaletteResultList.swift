import SwiftUI

struct BrowserCommandPaletteResultList: View {
    let model: BrowserCommandPaletteModel
    let maximumResultAreaHeight: CGFloat

    private var resultAreaHeight: CGFloat {
        BrowserCommandPaletteLayout.resultAreaHeight(
            sectionRowCounts: model.resultGroups
                .filter { $0.header != nil }
                .map(\.items.count),
            includesPrimaryAction: model.resultGroups.contains { $0.header == nil },
            maximumHeight: maximumResultAreaHeight
        )
    }

    var body: some View {
        ScrollView {
            VStack(
                alignment: .leading,
                spacing: BrowserCommandPaletteMetrics.resultGroupSpacing
            ) {
                ForEach(model.resultGroups) { group in
                    BrowserCommandPaletteResultGroupView(
                        model: model,
                        group: group
                    )
                }
            }
            .padding(BrowserCommandPaletteMetrics.resultContentPadding)
        }
        .frame(height: resultAreaHeight)
        .clipped()
    }
}
