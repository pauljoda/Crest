import SwiftUI

struct BrowserCommandPaletteResultList: View {
    let model: BrowserCommandPaletteModel
    let maximumResultAreaHeight: CGFloat
    /// The results take all the height they may, however few there are.
    var fillsHeight = false
    /// The results run upward from the field below them: the last group on
    /// top and each group's rows from the bottom, so the best match sits
    /// nearest the field, and the list starts scrolled to the bottom.
    var listsUpward = false

    private var resultAreaHeight: CGFloat {
        guard !fillsHeight else { return maximumResultAreaHeight }
        return BrowserCommandPaletteLayout.resultAreaHeight(
            groups: model.groups.map { ($0.section.title != nil, $0.items.count) },
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
                    ForEach(listsUpward ? model.groups.reversed() : model.groups) { group in
                        BrowserCommandPaletteResultGroupView(
                            model: model,
                            group: group,
                            listsUpward: listsUpward
                        )
                    }
                }
                .padding(BrowserCommandPaletteMetrics.resultContentPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .defaultScrollAnchor(listsUpward ? .bottom : .top)
            .frame(height: resultAreaHeight)
            .clipped()
            .onChange(of: model.keyboardSelectionRevision) { _, _ in
                revealSelection(using: reader)
            }
            .onChange(of: model.items) { _, _ in
                revealSelection(using: reader)
            }
        }
    }

    private func revealSelection(using reader: ScrollViewProxy) {
        guard model.items.indices.contains(model.selectedResultIndex) else { return }
        // A nil anchor moves only as far as needed to reveal the row. Hover
        // selection deliberately does not initiate scrolling under the pointer.
        reader.scrollTo(model.items[model.selectedResultIndex].id)
    }
}
