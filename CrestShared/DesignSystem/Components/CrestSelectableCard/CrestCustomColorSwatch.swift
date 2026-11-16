import SwiftUI

/// The last swatch of a row of colors: a circle the size of the others that
/// opens the system color picker, for a color of the person's own. It wears
/// that color, ringed, while it is the one chosen, and a plus before.
struct CrestCustomColorSwatch: View {
    // MARK: - Variables

    let title: LocalizedStringResource
    @Binding var color: Color
    let isSelected: Bool
    var diameter: CGFloat = 28
    var tint: Color? = nil

    @State private var isHovering = false

    // MARK: - Actions - Drawing

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    isSelected
                        ? AnyShapeStyle(color) : AnyShapeStyle(isHovering ? CrestColor.hover : CrestColor.chromeSurface)
                )
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: diameter * 0.42, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .opacity(isSelected ? 0 : 1)
                }
                .overlay { Circle().strokeBorder(CrestBrandTheme.line, lineWidth: CrestLayout.hairline) }
                .frame(width: diameter, height: diameter)
                .padding(CrestSelectableCardDensity.swatch.padding)
                .overlay {
                    Circle()
                        .strokeBorder(
                            tint ?? CrestBrandTheme.accent, lineWidth: CrestSelectableCardMetrics.selectedBorderWidth
                        )
                        .opacity(isSelected ? 1 : 0)
                }
                .accessibilityHidden(true)
            // The system picker sits over the circle, all but clear, so a
            // click or tap on the circle is a click on the picker itself.
            ColorPicker(String(localized: title), selection: $color, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.6)
                .opacity(0.02)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .onHover { isHovering = $0 }
        .help(Text(title))
    }
}

#if DEBUG
    #Preview("Custom color swatch") {
        @Previewable @State var color = Color.orange
        @Previewable @State var chosen = false
        HStack(spacing: 16) {
            CrestCustomColorSwatch(title: "Custom color", color: $color, isSelected: false)
            CrestCustomColorSwatch(title: "Custom color", color: $color, isSelected: true)
            Toggle("Chosen", isOn: $chosen)
            CrestCustomColorSwatch(title: "Custom color", color: $color, isSelected: chosen)
        }
        .padding(32)
    }
#endif
