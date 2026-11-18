import SwiftUI

/// A circle that wears a color, one color or a gradient, and opens the color
/// popover to change it. Every color Crest lets a person pick sits in one.
struct CrestColorWell: View {
    // MARK: - Variables

    let title: LocalizedStringResource
    @Binding var fill: CrestColorFill
    /// How strongly grain lies over the colors, which the popover sets too;
    /// nil for a well without texture.
    var texture: Binding<Double>? = nil
    var diameter: CGFloat = 30

    @State private var isOpen = false

    // MARK: - Actions - Drawing

    var body: some View {
        CrestSelectableCard(isSelected: isOpen, accessibilityLabel: Text(title), density: .swatch, tint: nil) {
            isOpen.toggle()
        } content: {
            Circle()
                .fill(fill.style)
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
                .frame(width: diameter, height: diameter)
        }
        // The popover hangs below the well, so growing for a gradient's
        // controls extends it downward and never moves what it shows.
        .crestPopover(isPresented: $isOpen, arrowEdge: .bottom) {
            // A phone keeps the picker beside the well rather than on a sheet
            // of its own, which would leave it a small card on an empty page.
            CrestColorPopover(fill: $fill, texture: texture)
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityValue(Text(fill.isGradient ? "Gradient" : "Color"))
        .help(Text(title))
    }
}

#if DEBUG
    #Preview("Color wells") {
        @Previewable @State var background = CrestColorFill([.indigo, .sky], kind: .linear, degrees: 90)
        @Previewable @State var accent = CrestColorFill(.sand)
        HStack(spacing: 24) {
            CrestColorWell(title: "Color", fill: $background)
            CrestColorWell(title: "Accent", fill: $accent)
        }
        .padding(40)
    }
#endif
