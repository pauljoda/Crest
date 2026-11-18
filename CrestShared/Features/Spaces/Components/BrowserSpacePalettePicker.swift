import SwiftUI

/// The palettes a Space can take in one tap, each a small sidebar in its
/// Background with a dot of its Accent. Setup's Space page and a Space's
/// appearance in Settings both show them.
struct BrowserSpacePalettePicker: View {
    // MARK: - Variables

    /// Whether the Space, or every Space the picker colors, wears a palette.
    let isWorn: (BrowserSpacePalette) -> Bool
    /// Gives the Space, or every Space the picker colors, a palette.
    let choose: (BrowserSpacePalette) -> Void

    // MARK: - Initializers

    /// A picker for one Space's look.
    init(branding: Binding<SpaceBranding>) {
        isWorn = { $0.isWorn(by: branding.wrappedValue) }
        choose = { branding.wrappedValue = $0.applying(to: branding.wrappedValue) }
    }

    /// A picker that colors as `choose` does, such as every Space setup makes.
    init(isWorn: @escaping (BrowserSpacePalette) -> Bool, choose: @escaping (BrowserSpacePalette) -> Void) {
        self.isWorn = isWorn
        self.choose = choose
    }

    // MARK: - Actions - Drawing

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: BrowserSpacePalettePickerMetrics.column), spacing: 6)], spacing: 6
        ) {
            ForEach(BrowserSpacePalette.all) { palette in
                CrestSelectableCard(
                    isSelected: isWorn(palette), accessibilityLabel: Text(palette.title), density: .compact, tint: nil
                ) {
                    choose(palette)
                } content: {
                    VStack(spacing: BrowserSpacePalettePickerMetrics.titleSpacing) {
                        swatch(palette)
                        Text(palette.title)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .help(Text(palette.title))
                .accessibilityIdentifier("space-palette-\(palette.name)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityIdentifier("space-palettes")
    }

    /// A short sidebar in the palette's Background, its Accent a dot where a
    /// Space's icon sits.
    private func swatch(_ palette: BrowserSpacePalette) -> some View {
        RoundedRectangle(cornerRadius: BrowserSpacePalettePickerMetrics.cornerRadius, style: .continuous)
            .fill(palette.backgroundFill.style)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(palette.accentFill.style)
                    .frame(
                        width: BrowserSpacePalettePickerMetrics.accentDot,
                        height: BrowserSpacePalettePickerMetrics.accentDot
                    )
                    .padding(.leading, BrowserSpacePalettePickerMetrics.accentInset)
            }
            .overlay {
                RoundedRectangle(cornerRadius: BrowserSpacePalettePickerMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline)
            }
            .frame(height: BrowserSpacePalettePickerMetrics.swatchHeight)
    }
}

enum BrowserSpacePalettePickerMetrics {
    static let column: CGFloat = 64
    static let swatchHeight: CGFloat = 24
    static let titleSpacing: CGFloat = 4
    static let cornerRadius: CGFloat = 6
    static let accentDot: CGFloat = 10
    static let accentInset: CGFloat = 7
}
