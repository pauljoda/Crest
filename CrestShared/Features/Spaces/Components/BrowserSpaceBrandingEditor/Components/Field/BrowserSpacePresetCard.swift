import SwiftUI

struct BrowserSpacePresetCard: View {
    let preset: BrowserSpaceBrandingPreset
    @Binding var branding: BrowserSpaceBranding

    var body: some View {
        BrowserSpaceOptionCard(
            title: preset.titleKey,
            spokenValue: Text(preset.colors.map(\.title).joined(separator: ", ")),
            isSelected: preset.isSelected(in: branding),
            identifier: "space-branding-preset-\(preset.title.lowercased())",
            tint: CrestBrandTheme.accent,
            select: { branding = preset.applying(to: branding) },
            artwork: {
                HStack(spacing: 0) {
                    ForEach(Array(preset.colors.enumerated()), id: \.offset) { _, color in
                        color.color
                    }
                }
                .frame(height: BrowserSpaceForgeMetrics.presetSwatchHeight)
                .clipShape(.capsule)
            }
        )
    }
}
