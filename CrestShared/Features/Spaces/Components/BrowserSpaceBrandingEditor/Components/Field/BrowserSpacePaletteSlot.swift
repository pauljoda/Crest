import SwiftUI

struct BrowserSpacePaletteSlot: View {
    let role: BrowserSpaceBrandColorRole
    let color: Binding<Color>?
    let canAdd: Bool
    let canRemove: Bool
    let compact: Bool
    let addColor: () -> Void
    let removeColor: () -> Void

    private var controlSize: CGFloat {
        compact
            ? BrowserSpaceForgeMetrics.compactPaletteControlSize
            : BrowserSpaceForgeMetrics.paletteControlSize
    }

    var body: some View {
        VStack(spacing: CrestSpacing.small) {
            if let color {
                ColorPicker(
                    role.title,
                    selection: color,
                    supportsOpacity: false
                )
                .labelsHidden()
                .scaleEffect(
                    compact
                        ? BrowserSpaceForgeMetrics.compactPaletteScale
                        : BrowserSpaceForgeMetrics.paletteScale
                )
                .frame(width: controlSize, height: controlSize)
                .accessibilityLabel(Text(role.title))
                .accessibilityIdentifier(
                    "space-branding-\(role.accessibilityIdentifierComponent)-color-picker"
                )
            } else {
                Button(role.addColorTitle, systemImage: "plus", action: addColor)
                    .labelStyle(.iconOnly)
                    .frame(width: controlSize, height: controlSize)
                    .background(.quaternary, in: .circle)
                    .disabled(!canAdd)
                    .opacity(canAdd ? 1 : CrestOpacity.disabled)
                    .accessibilityIdentifier(
                        "space-branding-add-\(role.accessibilityIdentifierComponent)-color"
                    )
            }

            Text(role.title)
                .font(CrestTypography.metadata)
                .lineLimit(1)
                .minimumScaleFactor(BrowserSpaceForgeMetrics.paletteLabelMinimumScale)

            if canRemove {
                Button(role.removeColorTitle, systemImage: "minus.circle", action: removeColor)
                    .labelStyle(.iconOnly)
                    .buttonStyle(BrowserSettingsIconButtonStyle(tint: .secondary))
                    .accessibilityIdentifier(
                        "space-branding-remove-\(role.accessibilityIdentifierComponent)-color"
                    )
            } else {
                Color.clear
                    .frame(
                        width: BrowserSettingsControlPolicy.minimumTouchTarget,
                        height: BrowserSettingsControlPolicy.minimumTouchTarget
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(
            maxWidth: compact
                ? BrowserSpaceForgeMetrics.compactPaletteMaximumWidth
                : BrowserSpaceForgeMetrics.paletteMaximumWidth)
    }
}
