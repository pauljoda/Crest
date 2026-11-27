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

    /// The rows' own height as laid out, which text size and platform make
    /// taller or shorter than the metrics estimate.
    @State private var contentHeight: CGFloat?

    /// The rows' height, at most `maximumResultAreaHeight`, past which they
    /// scroll.
    private var resultAreaHeight: CGFloat {
        guard !fillsHeight else { return maximumResultAreaHeight }
        let estimate = BrowserCommandPaletteLayout.resultAreaHeight(
            groups: model.groups.map { ($0.section.title != nil, $0.items.count) },
            maximumHeight: .infinity
        )
        return min(contentHeight ?? estimate, max(0, maximumResultAreaHeight))
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: BrowserCommandPaletteMetrics.resultSectionSpacing
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
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: { newHeight in
                    guard !fillsHeight, contentHeight != newHeight else { return }
                    contentHeight = newHeight
                }
            }
            .defaultScrollAnchor(listsUpward ? .bottom : .top)
            // The scroll bar stays clear of the card's rounded corners.
            .contentMargins(.vertical, BrowserCommandPaletteMetrics.resultContentPadding, for: .scrollIndicators)
            // Scrolling can bring a row under a resting pointer, which only
            // the pointer's next move may select.
            .onScrollGeometryChange(for: CGFloat.self) {
                $0.contentOffset.y
            } action: { _, _ in
                model.resultsScrolled()
            }
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
