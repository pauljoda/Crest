import SwiftUI

struct CrestSpaceChipSurface<LabelContent: View>: View {
    let tint: Color
    let isSelected: Bool
    let isPressed: Bool
    let label: LabelContent

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: CrestSpaceChipMetrics.cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        label
            .font(
                CrestTypography.sans(
                    CrestButtonMetrics.standardLabelSize,
                    weight: isSelected ? .bold : .medium
                )
            )
            .foregroundStyle(CrestBrandTheme.textDisplay)
            .padding(.horizontal, CrestSpaceChipMetrics.horizontalPadding)
            .frame(height: CrestSpaceChipMetrics.height)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected
                        ? tint.opacity(CrestSpaceChipMetrics.selectedStrokeOpacity)
                        : CrestBrandTheme.line,
                    lineWidth: isSelected
                        ? CrestSpaceChipMetrics.selectedStrokeWidth
                        : CrestSpaceChipMetrics.restingStrokeWidth
                )
            }
            .contentShape(
                .rect(
                    cornerRadius: CrestSpaceChipMetrics.cornerRadius,
                    style: .continuous
                )
            )
            .crestFocusShape(shape)
            .crestPressFeedback(
                isPressed: isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    private var fill: Color {
        if isSelected {
            return tint.opacity(
                isPressed
                    ? CrestButtonMetrics.tintPressedFill
                    : CrestButtonMetrics.tintEmphasizedFill
            )
        }
        if isPressed || isHovering {
            return CrestBrandTheme.surface
        }
        return CrestBrandTheme.canvas
    }
}

#Preview("Space Chip Surface", traits: .sizeThatFitsLayout) {
    HStack {
        CrestSpaceChipSurface(
            tint: CrestSpaceSelectorPreviewFixture.workSpace.accent.color,
            isSelected: true,
            isPressed: false,
            label: Label("Work", systemImage: "briefcase.fill")
        )

        CrestSpaceChipSurface(
            tint: CrestSpaceSelectorPreviewFixture.privateSpace.accent.color,
            isSelected: false,
            isPressed: true,
            label: Label("Private", systemImage: "lock.fill")
        )
    }
    .padding()
    .environment(\.displayScale, 2)
    .preferredColorScheme(.light)
}
