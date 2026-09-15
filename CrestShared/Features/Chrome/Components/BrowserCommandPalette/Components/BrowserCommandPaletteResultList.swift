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
        ScrollViewReader { reader in
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
            .onChange(of: model.keyboardSelectionRevision) { _, _ in
                revealSelection(using: reader)
            }
            .onChange(of: model.results) { _, _ in
                revealSelection(using: reader)
            }
        }
    }

    private func revealSelection(using reader: ScrollViewProxy) {
        guard model.results.indices.contains(model.selectedResultIndex) else { return }
        // A nil anchor moves only as far as needed to reveal the row. Hover
        // selection deliberately does not initiate scrolling under the pointer.
        reader.scrollTo(model.results[model.selectedResultIndex].id)
    }
}
