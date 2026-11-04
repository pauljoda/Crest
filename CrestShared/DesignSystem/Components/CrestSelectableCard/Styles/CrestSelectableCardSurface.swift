import SwiftUI

struct CrestSelectableCardSurface: View {
    // MARK: - Variables

    let isSelected: Bool
    let density: CrestSelectableCardDensity
    let tint: Color?
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var isHovering = false

    var body: some View {
        let tint = tint ?? CrestBrandTheme.accent
        let shape = CrestSelectableCardShape(cornerRadius: density.cornerRadius)

        configuration.label
            .padding(density.padding)
            .frame(maxWidth: density.fillsWidth ? .infinity : nil)
            .background(background(tint: tint), in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? tint : CrestBrandTheme.line,
                    lineWidth: borderWidth
                )
            }
            .contentShape(shape)
            .crestFocusShape(shape)
            .crestPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .animation(
                CrestMotion.press.unlessReducingMotion(reduceMotion),
                value: isSelected
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    // MARK: - Actions - Drawing

    private var borderWidth: CGFloat {
        isSelected || contrast == .increased
            ? CrestSelectableCardMetrics.selectedBorderWidth
            : density.restingBorderWidth
    }

    private func background(tint: Color) -> Color {
        switch (isSelected, configuration.isPressed, isHovering) {
        case (true, true, _):
            tint.opacity(CrestButtonMetrics.tintEmphasizedFill)
        case (true, false, _):
            tint.opacity(CrestSelectableCardMetrics.selectedFillOpacity)
        case (false, true, _):
            CrestColor.selection
        case (false, false, true):
            CrestColor.hover
        case (false, false, false):
            density.showsRestingFill ? CrestColor.chromeSurface : .clear
        }
    }
}

#if DEBUG
    #Preview("Card surface") {
        @Previewable @State var selected = false
        CrestSelectableCard(isSelected: selected, accessibilityLabel: Text("Banner"), action: { selected.toggle() }) {
            Label("Banner", systemImage: "flag.fill").frame(maxWidth: .infinity, alignment: .leading)
        }.padding().frame(width: 320)
    }
#endif
