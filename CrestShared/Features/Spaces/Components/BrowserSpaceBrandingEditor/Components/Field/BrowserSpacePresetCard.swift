import SwiftUI

struct BrowserSpacePresetCard: View {
    let preset: BrowserSpaceBrandingPreset
    let isSelected: Bool
    var dense = false
    let select: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var preview: BrowserSpaceBranding {
        BrowserSpaceBranding(colors: preset.colors, iconStyle: .layeredCrest, crest: preset.crest)
    }

    var body: some View {
        Button(action: select) {
            VStack(spacing: dense ? 6 : CrestSpacing.small) {
                BrowserSpaceCrestIcon(branding: preview, size: dense ? 38 : 48)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, dense ? 4 : 6)
                    .background(preset.colors[0].color, in: .rect(cornerRadius: 12))
                HStack {
                    Text(preset.titleKey)
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? CrestBrandPalette.butter : .secondary)
                }
                .font(CrestTypography.sans(dense ? 12 : 13, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.bottom, 5)
            }
            .padding(dense ? 6 : CrestSpacing.small)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(
            BrowserOnboardingPalette.paper,
            in: .rect(cornerRadius: 16)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isSelected ? CrestBrandPalette.butter : BrowserOnboardingPalette.line, lineWidth: 2)
        }
        .scaleEffect(isHovering ? 1.025 : 1)
        .shadow(color: .black.opacity(isHovering ? 0.10 : 0), radius: 12, y: 5)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(preset.titleKey))
        .accessibilityValue(Text(preset.crest.symbol.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("space-branding-preset-\(preset.title.lowercased())")
    }
}
