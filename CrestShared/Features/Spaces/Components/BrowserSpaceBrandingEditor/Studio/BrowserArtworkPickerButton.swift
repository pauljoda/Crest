import SwiftUI

/// Shared sizing and presentation for the symbol and emoji library buttons:
/// a compact card of the design system's that opens the library.
struct BrowserArtworkPickerButton<Artwork: View>: View {
    // MARK: - Static Variables

    static var artworkSize: CGFloat { 36 }
    static var minimumContentHeight: CGFloat { 40 }

    // MARK: - Variables

    let title: LocalizedStringKey
    let detail: Text
    let action: () -> Void
    @ViewBuilder var artwork: () -> Artwork

    // MARK: - Actions - Drawing

    var body: some View {
        Button(action: action) {
            HStack(spacing: CrestSpacing.medium) {
                artwork()
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: Self.artworkSize, height: Self.artworkSize)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    Text(title).font(.body.weight(.medium))
                    detail.font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CrestFormDisclosureChevron()
            }
            .foregroundStyle(.primary)
            .frame(minHeight: Self.minimumContentHeight)
            // The card's own compact inset, and a little more, so the
            // artwork has room.
            .padding(CrestSpacing.extraSmall)
        }
        .buttonStyle(CrestSelectableCardStyle(isSelected: false, density: .compact))
    }
}
